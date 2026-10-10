USE lifecycle;

-- =====================================================================
-- MODEL LAYER  (Raw Tables -> Model Views -> Analysis SQL)
-- ---------------------------------------------------------------------
-- These views apply the business rules from Report Section 8.2
-- (Recharge Tier, Campaign Status, value-tier / lifecycle joins) ONCE,
-- so every downstream analysis query reads from a single governed source
-- instead of re-deriving the same logic each time.
-- Each view carries the fields needed by the campaign's analyses, so the
-- Section 10-13 analyses can all be rebuilt on top of these views.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. model_fortune_users
--    Grain: one row per Fortune Recharge visitor.
--    Adds value tier, lifecycle stage, recharge tier, campaign status,
--    and leaderboard group on top of the raw behavior fields.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW model_fortune_users AS
SELECT
    f.user_id,

    u.user_value_tier,
    u.lifecycle_stage,

    -- funnel / behavior fields
    f.visit_flag,
    f.recharge_flag,
    f.campaign_recharge_amount,
    f.recharge_day_count,

    -- key sources (for 13.4 key distribution) + total
    f.key_earned_4day,
    f.key_earned_10k,
    f.key_earned_milestone,
    f.key_earned_total,

    -- lottery / leaderboard (for 13.5, 13.8)
    f.lottery_draw_count,
    f.wealth_coin,
    f.leaderboard_flag,
    f.leaderboard_rank,

    -- Recharge Tier (business rule: in-campaign spend)
    CASE
        WHEN f.campaign_recharge_amount = 0    THEN 'No Recharge'
        WHEN f.campaign_recharge_amount < 500  THEN 'Below 500'
        WHEN f.campaign_recharge_amount < 1000 THEN '500-999'
        WHEN f.campaign_recharge_amount < 1500 THEN '1000-1499'
        ELSE '1500+'
    END AS recharge_tier,

    -- Campaign Status (deepest funnel stage reached)
    CASE
        WHEN f.leaderboard_flag   = 1 THEN 'Leaderboard'
        WHEN f.lottery_draw_count > 0 THEN 'Lottery'
        WHEN f.key_earned_total   > 0 THEN 'Key Earned'
        WHEN f.recharge_flag      = 1 THEN 'Recharged'
        WHEN f.visit_flag         = 1 THEN 'Visited'
        ELSE 'Exposed'
    END AS campaign_status,

    CASE
        WHEN f.leaderboard_flag = 1 THEN 'Leaderboard User'
        ELSE 'Non-Leaderboard User'
    END AS leaderboard_group

FROM fortune_recharge_log f
LEFT JOIN user_profile u
    ON u.user_id = f.user_id;


-- ---------------------------------------------------------------------
-- 2. model_kings_users
--    Grain: one row per eligible King's Return user (the return-log is
--    already one row per eligible user, so it sets the grain).
--    Adds value tier and a per-user recharge total + band.
--    Note: kings_recharge_log is one row per TRANSACTION, so it is
--    aggregated to one row per user BEFORE the join to keep the grain.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW model_kings_users AS
SELECT
    r.user_id,
    k.user_value_tier,

    -- reactivation funnel (12.2)
    r.eligible_flag,
    r.return_login_flag,
    r.campaign_entry_flag,
    r.first_return_gift_received_flag,

    -- login milestones: cumulative days logged -> different reward tiers (12.3)
    r.login_3day_flag,
    r.login_7day_flag,
    r.login_14day_flag,
    r.login_30day_flag,
    r.claim_login_3day_reward_flag,
    r.claim_login_7day_reward_flag,
    r.claim_login_14day_reward_flag,
    r.claim_login_30day_reward_flag,

    -- recharge reward qualification + claim by tier (12.4)
    r.recharge_500_qualified_flag,
    r.recharge_1000_qualified_flag,
    r.recharge_5000_qualified_flag,
    r.recharge_10000_qualified_flag,
    r.recharge_50000_qualified_flag,
    r.recharge_100000_qualified_flag,
    r.claim_recharge_500_reward_flag,
    r.claim_recharge_1000_reward_flag,
    r.claim_recharge_5000_reward_flag,
    r.claim_recharge_10000_reward_flag,
    r.claim_recharge_50000_reward_flag,
    r.claim_recharge_100000_reward_flag,

    -- recharge revenue (12.6)
    COALESCE(rc.recharge_amount, 0) AS kings_recharge_amount,

    -- Recharge Band (King's uses wider bands than Fortune)
    CASE
        WHEN COALESCE(rc.recharge_amount, 0) = 0 THEN 'No Recharge'
        WHEN rc.recharge_amount < 1000   THEN '500-999'
        WHEN rc.recharge_amount < 5000   THEN '1000-4999'
        WHEN rc.recharge_amount < 10000  THEN '5000-9999'
        WHEN rc.recharge_amount < 50000  THEN '10000-49999'
        WHEN rc.recharge_amount < 100000 THEN '50000-99999'
        ELSE '100000+'
    END AS recharge_band

FROM kings_return_log_with_login_claims r
LEFT JOIN kings_user_profile k
    ON k.user_id = r.user_id
LEFT JOIN (
    -- aggregate transactions to one row per user before joining (grain alignment)
    SELECT
        user_id,
        SUM(recharge_amount) AS recharge_amount
    FROM kings_recharge_log
    GROUP BY user_id
) rc
    ON rc.user_id = r.user_id;


-- ---------------------------------------------------------------------
-- 3. model_puzzle_users
--    Grain: one row per Puzzle participant.
--    Adds value tier + lifecycle stage and pre-computes the funnel-stage
--    flags so Tableau can aggregate without CASE logic.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW model_puzzle_users AS
SELECT
    p.user_id,

    u.user_value_tier,
    u.lifecycle_stage,

    -- raw behavior
    p.daily_checkin_flag,
    p.recharge_chance_count,
    p.chance_count,
    p.puzzle_piece_count,
    p.completed_flag,
    p.random_reward_claim_count,
    p.grand_prize_claim_flag,

    -- funnel-stage flags (pre-derived for Tableau)
    CASE WHEN p.puzzle_piece_count > 0 THEN 1 ELSE 0 END AS participated_flag,

    -- deepest stage reached
    CASE
        WHEN p.grand_prize_claim_flag = 1 THEN 'Grand Prize'
        WHEN p.completed_flag         = 1 THEN 'Completed'
        WHEN p.puzzle_piece_count     > 0 THEN 'Participated'
        ELSE 'Attempt Only'
    END AS puzzle_status

FROM puzzle_event_log p
LEFT JOIN user_profile u
    ON u.user_id = p.user_id;


-- ---------------------------------------------------------------------
-- 4. model_checkin_users
--    Grain: one row per Check-in participant.
--    Adds value tier + lifecycle stage. The day1-7 flags are kept so
--    Tableau can build the per-check-in retention curve directly.
--    (In this data total_checkin_days = max_checkin_day, counts accrue
--    without gaps, so max is derivable; both are retained for convenience.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW model_checkin_users AS
SELECT
    c.user_id,

    u.user_value_tier,
    u.lifecycle_stage,

    c.unlock_flag,
    c.unlock_cost,
    c.total_checkin_days,
    c.max_checkin_day,

    -- per-check-in flags (Nth check-in reached) -> retention curve
    c.day1_flag,
    c.day2_flag,
    c.day3_flag,
    c.day4_flag,
    c.day5_flag,
    c.day6_flag,
    c.day7_flag,

    c.final_reward_claim_flag,

    -- Day-7 completion flag (pre-derived)
    c.day7_flag AS completed_d7_flag

FROM checkin_event_log c
LEFT JOIN user_profile u
    ON u.user_id = c.user_id;


-- =====================================================================
-- ANALYSIS LAYER  (examples -- every query now reads from a model view)
-- =====================================================================

-- Fortune: revenue by recharge tier  (rebuilds Report 13.3)
SELECT
    recharge_tier,
    COUNT(*)                      AS users,
    SUM(campaign_recharge_amount) AS revenue,
    ROUND(
        SUM(campaign_recharge_amount) * 100.0
        / SUM(SUM(campaign_recharge_amount)) OVER (),
        2
    ) AS revenue_contribution_pct
FROM model_fortune_users
GROUP BY recharge_tier
ORDER BY revenue DESC;


-- Fortune: key distribution by source  (rebuilds Report 13.4)
SELECT
    SUM(key_earned_4day)      AS keys_4day,
    SUM(key_earned_10k)       AS keys_10k,
    SUM(key_earned_milestone) AS keys_milestone,
    SUM(key_earned_total)     AS keys_total
FROM model_fortune_users;


-- Fortune: value-tier revenue & ARPPU  (rebuilds Report 13.6)
SELECT
    user_value_tier,
    SUM(CASE WHEN recharge_flag = 1 THEN 1 ELSE 0 END) AS recharge_users,
    SUM(campaign_recharge_amount)                      AS revenue,
    ROUND(
        SUM(campaign_recharge_amount) * 1.0
        / NULLIF(SUM(recharge_flag), 0),
        2
    ) AS arppu
FROM model_fortune_users
GROUP BY user_value_tier;


-- King's: login-milestone claim rates  (rebuilds Report 12.3)
SELECT
    SUM(login_3day_flag)               AS qualified_3day,
    SUM(claim_login_3day_reward_flag)  AS claimed_3day,
    SUM(login_7day_flag)               AS qualified_7day,
    SUM(claim_login_7day_reward_flag)  AS claimed_7day,
    SUM(login_14day_flag)              AS qualified_14day,
    SUM(claim_login_14day_reward_flag) AS claimed_14day,
    SUM(login_30day_flag)              AS qualified_30day,
    SUM(claim_login_30day_reward_flag) AS claimed_30day
FROM model_kings_users;


-- King's: revenue & contribution by value tier  (rebuilds Report 12.6)
SELECT
    user_value_tier,
    SUM(CASE WHEN kings_recharge_amount > 0 THEN 1 ELSE 0 END) AS rechargers,
    SUM(kings_recharge_amount)                                 AS revenue,
    ROUND(
        SUM(kings_recharge_amount) * 100.0
        / SUM(SUM(kings_recharge_amount)) OVER (),
        2
    ) AS contribution_pct
FROM model_kings_users
GROUP BY user_value_tier;


-- King's: reactivation funnel by recharge band
SELECT
    recharge_band,
    COUNT(*)                 AS users,
    SUM(return_login_flag)   AS returned,
    SUM(campaign_entry_flag) AS entered,
    SUM(login_30day_flag)    AS retained_30d
FROM model_kings_users
GROUP BY recharge_band
ORDER BY users DESC;


-- Puzzle: completion rate by value tier  (rebuilds Report 10.3)
SELECT
    user_value_tier,
    SUM(participated_flag)                              AS participants,
    SUM(completed_flag)                                AS completed,
    ROUND(
        SUM(completed_flag) * 100.0
        / NULLIF(SUM(participated_flag), 0),
        2
    ) AS completion_pct
FROM model_puzzle_users
GROUP BY user_value_tier;


-- Check-in: per-check-in retention curve  (rebuilds Report 11.1)
SELECT
    SUM(day1_flag) AS d1,
    SUM(day2_flag) AS d2,
    SUM(day3_flag) AS d3,
    SUM(day4_flag) AS d4,
    SUM(day5_flag) AS d5,
    SUM(day6_flag) AS d6,
    SUM(day7_flag) AS d7
FROM model_checkin_users;


-- Check-in: Day-7 completion by value tier  (rebuilds Report 11.3)
SELECT
    user_value_tier,
    SUM(unlock_flag)                                   AS unlock_users,
    SUM(completed_d7_flag)                             AS d7_users,
    ROUND(
        SUM(completed_d7_flag) * 100.0
        / NULLIF(SUM(unlock_flag), 0),
        2
    ) AS completion_pct
FROM model_checkin_users
GROUP BY user_value_tier;
