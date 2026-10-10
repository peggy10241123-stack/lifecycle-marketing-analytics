USE lifecycle;


-- 1. Cross-Campaign Overview
SELECT
    'Puzzle Event' AS campaign,
    'Engagement' AS objective,

    (SELECT COUNT(DISTINCT user_id)
     FROM campaign_exposure
     WHERE campaign_name = 'Puzzle Event') AS exposed_eligible,

    (SELECT COUNT(DISTINCT user_id)
     FROM campaign_exposure
     WHERE campaign_name = 'Puzzle Event' AND visit_flag = 1) AS visited_returned,

    (SELECT COUNT(DISTINCT user_id)
     FROM puzzle_event_log) AS participated_entered,

    (SELECT COUNT(DISTINCT user_id)
     FROM recharge_log
     WHERE campaign_name = 'Puzzle Event') AS recharge_users,

    (SELECT SUM(recharge_amount)
     FROM recharge_log
     WHERE campaign_name = 'Puzzle Event') AS revenue,

    ROUND(
        (SELECT SUM(recharge_amount) FROM recharge_log WHERE campaign_name = 'Puzzle Event') * 1.0
        / (SELECT COUNT(DISTINCT user_id) FROM recharge_log WHERE campaign_name = 'Puzzle Event'),
        2
    ) AS arppu

UNION ALL
SELECT
    '7-Day Check-in',
    'Retention',
    (SELECT COUNT(DISTINCT user_id) FROM campaign_exposure WHERE campaign_name = '7-Day Check-in'),
    (SELECT COUNT(DISTINCT user_id) FROM campaign_exposure WHERE campaign_name = '7-Day Check-in' AND visit_flag = 1),
    (SELECT COUNT(DISTINCT user_id) FROM checkin_event_log),
    NULL,   -- recharge_users: Check-in's recharge_log rows are unlock fees, not revenue
    NULL,   -- revenue
    NULL    -- arppu

UNION ALL
SELECT
    'Fortune Recharge',
    'Monetization',
    (SELECT COUNT(DISTINCT user_id) FROM campaign_exposure WHERE campaign_name = 'Fortune Recharge'),
    (SELECT COUNT(DISTINCT user_id) FROM fortune_recharge_log),                 -- visitors
    (SELECT SUM(recharge_flag) FROM fortune_recharge_log),                      -- rechargers
    (SELECT SUM(recharge_flag) FROM fortune_recharge_log),
    (SELECT SUM(campaign_recharge_amount) FROM fortune_recharge_log),
    ROUND(
        (SELECT SUM(campaign_recharge_amount) FROM fortune_recharge_log) * 1.0
        / (SELECT SUM(recharge_flag) FROM fortune_recharge_log),
        2
    )

UNION ALL
SELECT
    'King''s Return',
    'Win-back',
    (SELECT COUNT(*) FROM kings_return_log_with_login_claims WHERE eligible_flag = 1),
    (SELECT SUM(return_login_flag) FROM kings_return_log_with_login_claims),
    (SELECT SUM(campaign_entry_flag) FROM kings_return_log_with_login_claims),
    (SELECT COUNT(DISTINCT user_id) FROM kings_recharge_log),
    (SELECT SUM(recharge_amount) FROM kings_recharge_log),
    ROUND(
        (SELECT SUM(recharge_amount) FROM kings_recharge_log) * 1.0
        / (SELECT COUNT(DISTINCT user_id) FROM kings_recharge_log),
        2
    );


-- 2.Puzzle Event Analysis
-- 2.1 Puzzle Funnel Analysis
WITH funnel AS (

    SELECT
        1 AS stage_order,
        'Exposure' AS funnel_stage,
        COUNT(DISTINCT user_id) AS users
    FROM campaign_exposure
    WHERE campaign_name = 'Puzzle Event'

    UNION ALL

    SELECT
        2,
        'Visit',
        COUNT(DISTINCT user_id)
    FROM campaign_exposure
    WHERE campaign_name = 'Puzzle Event'
      AND visit_flag = 1

    UNION ALL

    SELECT
        3,
        'Participation',
        COUNT(DISTINCT user_id)
    FROM puzzle_event_log

    UNION ALL

    SELECT
        4,
        'Completion',
        COUNT(DISTINCT user_id)
    FROM puzzle_event_log
    WHERE completed_flag = 1

    UNION ALL

    SELECT
        5,
        'Grand Prize Claim',
        COUNT(DISTINCT user_id)
    FROM puzzle_event_log
    WHERE grand_prize_claim_flag = 1
)

SELECT
    funnel_stage,
    users,

    ROUND(
        users * 100.0 /
        LAG(users) OVER (ORDER BY stage_order),
        2
    ) AS conversion_rate,

    LAG(users) OVER (ORDER BY stage_order) - users AS drop_off_users

FROM funnel

ORDER BY stage_order;


-- 2.2 Puzzle Recharge Impact Analysis
-- Revenue Performance
SELECT
    COUNT(DISTINCT p.user_id) AS participants,

    COUNT(DISTINCT r.user_id) AS recharge_users,

    ROUND(
        COUNT(DISTINCT r.user_id) * 100.0
        / COUNT(DISTINCT p.user_id),
        2
    ) AS recharge_conversion_rate,

    SUM(r.recharge_amount) AS total_revenue,

    ROUND(
        SUM(r.recharge_amount)
        / COUNT(DISTINCT r.user_id),
        2
    ) AS arppu

FROM puzzle_event_log p

LEFT JOIN recharge_log r
ON p.user_id = r.user_id
AND r.campaign_name = 'Puzzle Event';


-- 2.3 Puzzle User Value Analysis
-- User Value — Participation Rate
SELECT
    u.user_value_tier,

    COUNT(DISTINCT p.user_id) AS participants,

    COUNT(DISTINCT u.user_id) AS total_users,

    ROUND(
        COUNT(DISTINCT p.user_id) * 100.0
        / COUNT(DISTINCT u.user_id),
        2
    ) AS participation_rate

FROM user_profile u

LEFT JOIN puzzle_event_log p
ON u.user_id = p.user_id

GROUP BY u.user_value_tier

ORDER BY participation_rate DESC;

-- User Value — Completion Rate
SELECT
    u.user_value_tier,

    COUNT(DISTINCT p.user_id) AS participants,

    SUM(p.completed_flag) AS completed_users,

    ROUND(
        SUM(p.completed_flag) * 100.0
        / COUNT(DISTINCT p.user_id),
        2
    ) AS completion_rate

FROM puzzle_event_log p

JOIN user_profile u
ON p.user_id = u.user_id

GROUP BY u.user_value_tier

ORDER BY completion_rate DESC;

-- 2.4 Puzzle: Lifecycle Stage Analysis
SELECT u.lifecycle_stage,
       COUNT(DISTINCT u.user_id) AS stage_users,
       COUNT(DISTINCT p.user_id) AS participants,
       ROUND(100.0*COUNT(DISTINCT p.user_id)/COUNT(DISTINCT u.user_id),1) AS particip_rate_pct
FROM user_profile u LEFT JOIN puzzle_event_log p ON p.user_id=u.user_id
GROUP BY u.lifecycle_stage;

SELECT u.lifecycle_stage, COUNT(*) AS participants,
       ROUND(100.0*SUM(p.completed_flag)/COUNT(*),1) AS completion_pct
FROM puzzle_event_log p JOIN user_profile u ON u.user_id=p.user_id
GROUP BY u.lifecycle_stage ORDER BY completion_pct DESC;

-- 3.Seven-Day Check-in Analysis
-- 3.1 Check-in Funnel Analysis
WITH funnel AS (

    SELECT
        1 AS stage_order,
        'Exposure' AS funnel_stage,
        COUNT(DISTINCT user_id) AS users
    FROM campaign_exposure
    WHERE campaign_name = '7-Day Check-in'

    UNION ALL

    SELECT
        2,
        'Visit',
        COUNT(DISTINCT user_id)
    FROM campaign_exposure
    WHERE campaign_name = '7-Day Check-in'
      AND visit_flag = 1

    UNION ALL

    SELECT
        3,
        'Unlock',
        COUNT(DISTINCT user_id)
    FROM checkin_event_log

    UNION ALL

    SELECT 4, 'Day 1', SUM(day1_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 5, 'Day 2', SUM(day2_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 6, 'Day 3', SUM(day3_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 7, 'Day 4', SUM(day4_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 8, 'Day 5', SUM(day5_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 9, 'Day 6', SUM(day6_flag)
    FROM checkin_event_log

    UNION ALL

    SELECT 10, 'Day 7 / Final Reward', SUM(day7_flag)
    FROM checkin_event_log
)

SELECT
    funnel_stage,
    users,

    ROUND(
        users * 100.0 /
        LAG(users) OVER (ORDER BY stage_order),
        2
    ) AS conversion_rate,

    LAG(users) OVER (ORDER BY stage_order) - users AS drop_off_users

FROM funnel
ORDER BY stage_order;
        

-- 3.2 Check-in User Value Analysis
-- User Value — Unlock Rate
SELECT
    u.user_value_tier,

    COUNT(DISTINCT c.user_id) AS unlocked_users,

    COUNT(DISTINCT u.user_id) AS total_users,

    ROUND(
        COUNT(DISTINCT c.user_id) * 100.0
        / COUNT(DISTINCT u.user_id),
        2
    ) AS unlock_rate

FROM user_profile u

LEFT JOIN checkin_event_log c
ON u.user_id = c.user_id

GROUP BY u.user_value_tier

ORDER BY unlock_rate DESC;

-- User Value — Day 7 Completion Rate
SELECT
    u.user_value_tier,

    COUNT(DISTINCT c.user_id) AS unlocked_users,

    SUM(c.day7_flag) AS day7_users,

    ROUND(
        SUM(c.day7_flag) * 100.0
        / COUNT(DISTINCT c.user_id),
        2
    ) AS day7_completion_rate

FROM checkin_event_log c

JOIN user_profile u
ON c.user_id = u.user_id

GROUP BY u.user_value_tier

ORDER BY day7_completion_rate DESC;

-- Average Check-in Days
SELECT
    u.user_value_tier,

    COUNT(DISTINCT c.user_id) AS unlocked_users,

    ROUND(
        AVG(c.total_checkin_days),
        2
    ) AS avg_checkin_days

FROM checkin_event_log c

JOIN user_profile u
ON c.user_id = u.user_id

GROUP BY u.user_value_tier

ORDER BY avg_checkin_days DESC;

-- 3.3 Check-in Lifecycle Stage Analysis
SELECT 
	u.lifecycle_stage, 
	COUNT(*) AS unlocked_users,
	ROUND(100.0*SUM(c.day7_flag)/COUNT(*),1) AS d7_rate_pct
FROM checkin_event_log c 
JOIN user_profile u 
	ON u.user_id=c.user_id
GROUP BY u.lifecycle_stage 
ORDER BY d7_rate_pct DESC;

-- 4.King's Return Analysis
-- 4.1 King's Return Exposure Performance
SELECT
    COUNT(DISTINCT user_id) AS exposure_users,

    COUNT(DISTINCT CASE WHEN visit_flag = 1 THEN user_id END) AS visit_users,

    ROUND(
        COUNT(DISTINCT CASE WHEN visit_flag = 1 THEN user_id END) * 100.0
        / COUNT(DISTINCT user_id),
        2
    ) AS visit_rate

FROM kings_campaign_exposure;

-- 4.2 King's Return Retention Funnel & Reactivation
WITH funnel AS (

    SELECT 1 AS stage_order,
           'Eligible Users' AS funnel_stage,
           COUNT(*) AS users
    FROM kings_return_log_with_login_claims
    WHERE eligible_flag = 1
    

    UNION ALL
    
    SELECT 2,
        'Campaign Exposure',
        COUNT(DISTINCT user_id)
    FROM kings_campaign_exposure
    
    UNION ALL

    SELECT 3,
           'Return Login',
           SUM(return_login_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT 4,
           'Campaign Entry',
           SUM(campaign_entry_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT 5,
           'Gift Claimed',
           SUM(first_return_gift_received_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT 6,
           'Login 30 Days',
           SUM(login_30day_flag)
    FROM kings_return_log_with_login_claims
)

SELECT
    funnel_stage,
    users,

    ROUND(
        users * 100.0 /
        LAG(users) OVER (ORDER BY stage_order),
        2
    ) AS conversion_rate,

    LAG(users) OVER (ORDER BY stage_order) - users
    AS drop_off_users

FROM funnel
ORDER BY stage_order;

SELECT
    COUNT(*) AS eligible_users,
    SUM(return_login_flag) AS return_users,
    ROUND(
        SUM(return_login_flag) * 100.0 /
        COUNT(*),
        2
    ) AS overall_reactivation_rate
FROM kings_return_log_with_login_claims
WHERE eligible_flag = 1;


-- 4.3 King's Return Reward Claim Analysis
-- Login Reward Claim
WITH reward_claim AS (

    SELECT
        '3 Day Reward' AS reward_stage,
        SUM(login_3day_flag) AS qualified_users,
        SUM(claim_login_3day_reward_flag) AS claimed_users
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        '7 Day Reward',
        SUM(login_7day_flag),
        SUM(claim_login_7day_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        '14 Day Reward',
        SUM(login_14day_flag),
        SUM(claim_login_14day_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        '30 Day Reward',
        SUM(login_30day_flag),
        SUM(claim_login_30day_reward_flag)
    FROM kings_return_log_with_login_claims
)

SELECT
    reward_stage,
    qualified_users,
    claimed_users,
    ROUND(
        claimed_users * 100.0 / qualified_users,
        2
    ) AS claim_rate
FROM reward_claim;

-- Recharge Reward Claim
WITH reward_claim AS (

    SELECT
        'Recharge 500' AS milestone,
        SUM(recharge_500_qualified_flag) AS qualified_users,
        SUM(claim_recharge_500_reward_flag) AS claimed_users
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        'Recharge 1000',
        SUM(recharge_1000_qualified_flag),
        SUM(claim_recharge_1000_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        'Recharge 5000',
        SUM(recharge_5000_qualified_flag),
        SUM(claim_recharge_5000_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        'Recharge 10000',
        SUM(recharge_10000_qualified_flag),
        SUM(claim_recharge_10000_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        'Recharge 50000',
        SUM(recharge_50000_qualified_flag),
        SUM(claim_recharge_50000_reward_flag)
    FROM kings_return_log_with_login_claims

    UNION ALL

    SELECT
        'Recharge 100000',
        SUM(recharge_100000_qualified_flag),
        SUM(claim_recharge_100000_reward_flag)
    FROM kings_return_log_with_login_claims
)

SELECT
    milestone,
    qualified_users,
    claimed_users,

    ROUND(
        claimed_users * 100.0 / qualified_users,
        2
    ) AS claim_rate

FROM reward_claim;

-- 4.4 King's Return User Value Analysis
-- Return Rate by User Value
SELECT
    u.user_value_tier,

    COUNT(DISTINCT u.user_id) AS eligible_users,

    SUM(k.return_login_flag) AS return_users,

    ROUND(
        SUM(k.return_login_flag) * 100.0
        / COUNT(DISTINCT u.user_id),
        2
    ) AS return_rate

FROM kings_user_profile u

JOIN kings_return_log_with_login_claims k
ON u.user_id = k.user_id

GROUP BY u.user_value_tier

ORDER BY return_rate DESC;

-- 30-Day Retention by User Value
SELECT
    u.user_value_tier,

    SUM(k.campaign_entry_flag) AS campaign_entry_users,

    SUM(k.login_30day_flag) AS login_30day_users,

    ROUND(
        SUM(k.login_30day_flag) * 100.0
        / NULLIF(SUM(k.campaign_entry_flag),0),
        2
    ) AS day30_retention_rate

FROM kings_user_profile u

JOIN kings_return_log_with_login_claims k
ON u.user_id = k.user_id

GROUP BY u.user_value_tier

ORDER BY day30_retention_rate DESC;

-- Recharge Conversion by User Value
SELECT
    u.user_value_tier,

    SUM(k.campaign_entry_flag) AS campaign_entry_users,

    SUM(k.recharge_500_qualified_flag) AS recharge_users,

    ROUND(
        SUM(k.recharge_500_qualified_flag) * 100.0
        / NULLIF(SUM(k.campaign_entry_flag),0),
        2
    ) AS recharge_conversion_rate

FROM kings_user_profile u

JOIN kings_return_log_with_login_claims k
ON u.user_id = k.user_id

GROUP BY u.user_value_tier

ORDER BY recharge_conversion_rate DESC;

-- 4.5 King's Return Recharge Revenue Analysis
-- Overall
SELECT 
	COUNT(DISTINCT user_id) AS rechargers, 
    SUM(recharge_amount) AS revenue
FROM kings_recharge_log; 

-- By value tier
SELECT 
	k.user_value_tier,
	COUNT(DISTINCT r.user_id) AS rechargers,
	SUM(r.recharge_amount)    AS revenue,
	ROUND(100.0*SUM(r.recharge_amount)/SUM(SUM(r.recharge_amount)) OVER (),1) AS contrib_pct,
	ROUND(SUM(r.recharge_amount)/COUNT(DISTINCT r.user_id),0) AS mean_arppu
FROM kings_recharge_log r 
JOIN kings_user_profile k 
ON k.user_id=r.user_id
GROUP BY k.user_value_tier;

-- 5.Fortune Recharge Analysis
-- 5.1 Fortune Recharge Funnel Analysis
WITH funnel AS (

    SELECT
        1 AS stage_order,
        'Exposure' AS stage,
        COUNT(DISTINCT user_id) AS users
    FROM campaign_exposure
    WHERE campaign_name = 'Fortune Recharge'

    UNION ALL

    SELECT
        2,
        'Visit',
        COUNT(DISTINCT user_id)
    FROM campaign_exposure
    WHERE campaign_name = 'Fortune Recharge'
      AND visit_flag = 1

    UNION ALL

    SELECT
        3,
        'Recharge',
        COUNT(DISTINCT user_id)
    FROM fortune_recharge_log
    WHERE recharge_flag = 1

    UNION ALL

    SELECT
        4,
        'Earn Key',
        COUNT(DISTINCT user_id)
    FROM fortune_recharge_log
    WHERE key_earned_total > 0

    UNION ALL

    SELECT
        5,
        'Lottery Draw',
        COUNT(DISTINCT user_id)
    FROM fortune_recharge_log
    WHERE lottery_draw_count > 0

    UNION ALL

    SELECT
        6,
        'Leaderboard',
        COUNT(DISTINCT user_id)
    FROM fortune_recharge_log
    WHERE leaderboard_flag = 1
)

SELECT
    stage,
    users,
    ROUND(
        users * 100.0 / LAG(users) OVER (ORDER BY stage_order),
        2
    ) AS conversion_rate,
    LAG(users) OVER (ORDER BY stage_order) - users AS drop_off_users
FROM funnel
ORDER BY stage_order;

-- 5.2 Fortune Recharge Performance

SELECT
    COUNT(DISTINCT user_id) AS campaign_users,

    COUNT(DISTINCT CASE WHEN recharge_flag = 1 THEN user_id END) AS recharge_users,

    ROUND(
        COUNT(DISTINCT CASE WHEN recharge_flag = 1 THEN user_id END) * 100.0
        / COUNT(DISTINCT user_id),
        2
    ) AS recharge_conversion_rate,

    SUM(campaign_recharge_amount) AS total_revenue,

    ROUND(
        SUM(campaign_recharge_amount) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN recharge_flag = 1 THEN user_id END), 0),
        2
    ) AS arppu,

    ROUND(
        AVG(CASE WHEN recharge_flag = 1 THEN recharge_day_count END),
        2
    ) AS avg_recharge_days

FROM fortune_recharge_log;

-- 5.3 Recharge Tier Analysis
WITH recharge_tier AS (
    SELECT
        user_id,
        campaign_recharge_amount,
        CASE
            WHEN campaign_recharge_amount >= 1500 THEN '1500+'
            WHEN campaign_recharge_amount >= 1000 THEN '1000-1499'
            WHEN campaign_recharge_amount >= 500 THEN '500-999'
            WHEN campaign_recharge_amount > 0 THEN 'Below 500'
            ELSE 'No Recharge'
        END AS recharge_tier,
        CASE
            WHEN campaign_recharge_amount >= 1500 THEN 4
            WHEN campaign_recharge_amount >= 1000 THEN 3
            WHEN campaign_recharge_amount >= 500 THEN 2
            WHEN campaign_recharge_amount > 0 THEN 1
            ELSE 0
        END AS tier_order
    FROM fortune_recharge_log
)

SELECT
    recharge_tier,
    COUNT(DISTINCT user_id) AS users,
    SUM(campaign_recharge_amount) AS revenue,
    ROUND(
        SUM(campaign_recharge_amount) * 100.0 /
        (SELECT SUM(campaign_recharge_amount) FROM fortune_recharge_log),
        2
    ) AS revenue_contribution_rate,
    ROUND(
        SUM(campaign_recharge_amount) * 1.0 / COUNT(DISTINCT user_id),
        2
    ) AS avg_recharge_amount
FROM recharge_tier
GROUP BY recharge_tier, tier_order
ORDER BY tier_order;

-- 5.4 Key Distribution Analysis
WITH key_source AS (

    SELECT
        '4-Day Recharge Reward' AS key_source,
        SUM(key_earned_4day) AS keys_earned,
        1 AS source_order
    FROM fortune_recharge_log

    UNION ALL

    SELECT
        'Every 10K Recharge Reward',
        SUM(key_earned_10k),
        2
    FROM fortune_recharge_log

    UNION ALL

    SELECT
        'Recharge Milestone Reward',
        SUM(key_earned_milestone),
        3
    FROM fortune_recharge_log
)

SELECT
    key_source,
    keys_earned,
    ROUND(
        keys_earned * 100.0 /
        (SELECT SUM(keys_earned) FROM key_source),
        2
    ) AS key_contribution_rate
FROM key_source
ORDER BY source_order;

-- 5.5 Reward Mechanism Analysis

SELECT
    COUNT(DISTINCT CASE WHEN key_earned_total > 0 THEN user_id END) AS key_users,

    COUNT(DISTINCT CASE WHEN lottery_draw_count > 0 THEN user_id END) AS lottery_users,

    ROUND(
        COUNT(DISTINCT CASE WHEN lottery_draw_count > 0 THEN user_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN key_earned_total > 0 THEN user_id END), 0),
        2
    ) AS key_to_lottery_rate,

    COUNT(DISTINCT CASE WHEN leaderboard_flag = 1 THEN user_id END) AS leaderboard_users,

    ROUND(
        COUNT(DISTINCT CASE WHEN leaderboard_flag = 1 THEN user_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN lottery_draw_count > 0 THEN user_id END), 0),
        2
    ) AS lottery_to_leaderboard_rate,

    SUM(lottery_draw_count) AS total_lottery_draws,

    ROUND(
        SUM(lottery_draw_count) * 1.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN lottery_draw_count > 0 THEN user_id END), 0),
        2
    ) AS avg_draws_per_lottery_user

FROM fortune_recharge_log;

-- 5.6 User Value Analysis

SELECT
    u.user_value_tier,

    COUNT(DISTINCT f.user_id) AS recharge_users,

    SUM(f.campaign_recharge_amount) AS revenue,

    ROUND(
        SUM(f.campaign_recharge_amount) * 100.0 /
        NULLIF((SELECT SUM(campaign_recharge_amount) FROM fortune_recharge_log), 0),
        2
    ) AS revenue_contribution_rate,

    ROUND(
        SUM(f.campaign_recharge_amount) * 1.0 /
        NULLIF(COUNT(DISTINCT f.user_id), 0),
        2
    ) AS arppu,

    ROUND(AVG(f.recharge_day_count), 2) AS avg_recharge_days

FROM fortune_recharge_log f

JOIN user_profile u
ON f.user_id = u.user_id

WHERE f.recharge_flag = 1

GROUP BY u.user_value_tier

ORDER BY revenue DESC;

-- 5.7 Lifecycle Stage Analysis
SELECT 
	u.lifecycle_stage, 
    COUNT(*) AS visitors,
	ROUND(100.0*SUM(f.recharge_flag)/COUNT(*),1) AS recharge_conv_pct
FROM fortune_recharge_log f 
JOIN user_profile u 
	ON u.user_id=f.user_id
GROUP BY u.lifecycle_stage 
ORDER BY recharge_conv_pct DESC;

-- 5.8 Leaderboard Analysis
SELECT
    CASE
        WHEN leaderboard_flag = 1
        THEN 'Leaderboard Users'
        ELSE 'Non-Leaderboard Users'
    END AS user_group,

    COUNT(DISTINCT user_id) AS users,

    ROUND(
        AVG(campaign_recharge_amount),
        2
    ) AS avg_recharge_amount,

    ROUND(
        AVG(lottery_draw_count),
        2
    ) AS avg_draws,

    ROUND(
        AVG(wealth_coin),
        2
    ) AS avg_wealth_coin

FROM fortune_recharge_log

GROUP BY user_group

ORDER BY user_group;

-- 6. Overall Conclusions
-- One tidy long table: each campaign's headline metric by value tier.
-- (King's comes from its own dataset; pivot to the wide layout when presenting.)
WITH puzzle AS (
    SELECT
        'Puzzle: completion%' AS metric,
        u.user_value_tier AS tier,
        ROUND(
            SUM(p.completed_flag) * 100.0
            / COUNT(*),
            1
        ) AS rate_pct
    FROM puzzle_event_log p
    JOIN user_profile u ON u.user_id = p.user_id
    GROUP BY u.user_value_tier
),

checkin AS (
    SELECT
        'Check-in: D7%' AS metric,
        u.user_value_tier AS tier,
        ROUND(
            SUM(c.day7_flag) * 100.0
            / COUNT(*),
            1
        ) AS rate_pct
    FROM checkin_event_log c
    JOIN user_profile u ON u.user_id = c.user_id
    GROUP BY u.user_value_tier
),

fortune AS (
    SELECT
        'Fortune: recharge-conv%' AS metric,
        u.user_value_tier AS tier,
        ROUND(
            SUM(f.recharge_flag) * 100.0
            / COUNT(*),
            1
        ) AS rate_pct
    FROM fortune_recharge_log f
    JOIN user_profile u ON u.user_id = f.user_id
    GROUP BY u.user_value_tier
),

kings_return AS (
    SELECT
        'King''s: return%' AS metric,
        k.user_value_tier AS tier,
        ROUND(
            SUM(r.return_login_flag) * 100.0
            / SUM(r.eligible_flag),
            1
        ) AS rate_pct
    FROM kings_return_log_with_login_claims r
    JOIN kings_user_profile k ON k.user_id = r.user_id
    GROUP BY k.user_value_tier
),

kings_ret30 AS (
    SELECT
        'King''s: 30day-retention%' AS metric,
        k.user_value_tier AS tier,
        ROUND(
            SUM(CASE WHEN r.campaign_entry_flag = 1 THEN r.login_30day_flag END) * 100.0
            / NULLIF(SUM(r.campaign_entry_flag), 0),
            1
        ) AS rate_pct
    FROM kings_return_log_with_login_claims r
    JOIN kings_user_profile k ON k.user_id = r.user_id
    GROUP BY k.user_value_tier
)

SELECT * FROM puzzle
UNION ALL SELECT * FROM checkin
UNION ALL SELECT * FROM fortune
UNION ALL SELECT * FROM kings_return
UNION ALL SELECT * FROM kings_ret30
ORDER BY metric, tier;


-- 7. SMS Reactivation Analysis
-- =====================================================================
-- SMS Reactivation (always-on, content-only win-back of lapsed payers)
-- Source data is real operational data, scaled to this project's sample
-- size; all rates (delivery, reactivation, pay-through) are preserved.
-- Grain: one row per send batch (a send_date x churn_days bucket).
-- =====================================================================

DROP TABLE IF EXISTS sms_reactivation_log;

CREATE TABLE sms_reactivation_log (
    send_date       DATE,           -- batch send date
    churn_days      INT,            -- lapse depth targeted: 3 / 7 / 14 / 30 days
    sent            INT,            -- messages sent
    delivered       INT,            -- successfully delivered
    reactivated_7d  INT,            -- users who logged back in within 7 days
    pay_users_7d    INT,            -- reactivated users who paid within 7 days
    pay_amount_7d   DECIMAL(12,2),  -- 7-day revenue from reactivated users
    sms_cost        DECIMAL(10,2)   -- SMS send cost for the batch
);

INSERT INTO sms_reactivation_log
(send_date, churn_days, sent, delivered, reactivated_7d, pay_users_7d, pay_amount_7d, sms_cost) VALUES
('2024-06-27', 3, 72, 58, 31, 7, 3131.01, 3.01),
('2024-06-29', 3, 66, 54, 27, 6, 2751.3, 2.8),
('2024-07-01', 3, 54, 43, 22, 6, 2340.0, 2.24),
('2024-07-03', 3, 78, 60, 32, 7, 3082.15, 3.11),
('2024-07-05', 3, 80, 63, 32, 9, 3672.4, 3.3),
('2024-07-07', 3, 75, 60, 32, 8, 5076.37, 3.12),
('2024-07-09', 3, 57, 44, 25, 6, 2760.47, 2.31),
('2024-07-11', 3, 77, 60, 31, 8, 3013.13, 3.12),
('2024-07-13', 3, 71, 55, 30, 8, 3114.07, 0.0),
('2024-07-15', 3, 86, 67, 33, 7, 2909.53, 3.5),
('2024-07-17', 3, 50, 39, 30, 7, 1836.83, 2.04),
('2024-07-19', 3, 54, 41, 24, 6, 3239.6, 2.12),
('2024-07-21', 3, 57, 44, 25, 7, 3755.87, 2.29),
('2024-07-23', 3, 18, 14, 7, 2, 1149.27, 0.73),
('2024-07-25', 3, 68, 49, 30, 8, 5808.0, 2.56),
('2024-07-27', 3, 69, 16, 16, 7, 3281.6, 0.83),
('2024-07-29', 3, 16, 12, 0, 0, 0.0, 0.63),
('2024-07-31', 3, 17, 12, 0, 0, 0.0, 0.65),
('2024-08-02', 3, 56, 44, 31, 9, 4287.33, 2.29),
('2024-08-04', 3, 23, 17, 8, 2, 1528.67, 0.89),
('2024-08-06', 3, 17, 13, 0, 0, 0.0, 0.67),
('2024-08-08', 3, 50, 40, 30, 8, 3614.07, 2.05),
('2024-08-10', 3, 16, 12, 0, 0, 0.0, 0.61),
('2024-08-12', 3, 50, 38, 28, 8, 2888.07, 1.96),
('2024-08-14', 3, 18, 13, 0, 0, 0.0, 0.7),
('2024-08-16', 3, 46, 36, 26, 7, 2658.63, 1.88),
('2024-08-18', 3, 16, 12, 0, 0, 0.0, 0.61),
('2024-08-20', 3, 53, 40, 32, 8, 5746.53, 2.1),
('2024-08-22', 3, 16, 12, 0, 0, 0.0, 0.62),
('2024-08-24', 3, 52, 40, 30, 8, 3940.17, 2.09),
('2024-08-26', 3, 19, 14, 0, 0, 0.0, 0.74),
('2024-08-28', 3, 53, 41, 34, 9, 6060.13, 2.14),
('2024-08-30', 3, 19, 14, 0, 0, 0.0, 0.73),
('2024-09-01', 3, 43, 33, 24, 6, 2627.87, 1.71),
('2024-09-03', 3, 43, 32, 25, 7, 4878.0, 1.66),
('2024-09-05', 3, 16, 11, 0, 0, 0.0, 0.59),
('2024-09-07', 3, 47, 36, 27, 7, 3367.89, 1.88),
('2024-09-09', 3, 16, 12, 0, 0, 0.0, 0.64),
('2024-09-11', 3, 17, 9, 0, 0, 0.0, 0.49),
('2024-09-13', 3, 66, 38, 31, 8, 3693.07, 1.99),
('2024-09-15', 3, 68, 40, 34, 8, 2825.2, 2.07),
('2024-09-17', 3, 20, 11, 0, 0, 0.0, 0.59),
('2024-09-19', 3, 72, 41, 29, 7, 2846.27, 2.14),
('2024-09-21', 3, 20, 10, 0, 0, 0.0, 0.51),
('2024-09-23', 3, 16, 13, 0, 0, 0.0, 0.65),
('2024-09-25', 3, 50, 39, 31, 8, 3459.1, 2.03),
('2024-09-27', 3, 39, 29, 0, 0, 0.0, 1.49),
('2024-09-29', 3, 217, 104, 46, 9, 4892.0, 5.41),
('2024-10-01', 3, 22, 12, 0, 0, 0.0, 0.62),
('2024-10-03', 3, 75, 43, 36, 8, 3736.67, 2.24),
('2024-10-05', 3, 436, 339, 16, 4, 1999.6, 17.64),
('2024-10-07', 7, 88, 67, 28, 6, 2090.13, 3.48),
('2024-10-09', 7, 30, 22, 0, 0, 0.0, 1.15),
('2024-10-11', 7, 84, 65, 28, 6, 4118.53, 3.4),
('2024-10-13', 7, 30, 23, 0, 0, 0.0, 1.18),
('2024-10-15', 7, 98, 77, 33, 8, 3143.4, 3.98),
('2024-10-17', 7, 104, 81, 24, 6, 3718.93, 4.21),
('2024-10-19', 7, 144, 113, 30, 7, 2778.57, 5.87),
('2024-10-21', 7, 132, 104, 32, 7, 3715.02, 5.39),
('2024-10-23', 7, 136, 105, 30, 7, 2399.08, 5.47),
('2024-10-25', 7, 84, 66, 19, 4, 3416.67, 3.42),
('2024-10-27', 7, 132, 103, 34, 8, 4511.27, 5.35),
('2024-10-29', 7, 96, 82, 23, 6, 5925.73, 4.24),
('2024-10-31', 7, 35, 29, 8, 2, 1081.8, 1.52),
('2024-11-02', 7, 34, 18, 0, 0, 0.0, 0.94),
('2024-11-04', 7, 32, 24, 0, 0, 0.0, 1.27),
('2024-11-06', 7, 34, 25, 0, 0, 0.0, 1.29),
('2024-11-08', 7, 93, 72, 32, 8, 4017.73, 3.76),
('2024-11-10', 7, 87, 67, 31, 7, 2968.33, 3.48),
('2024-11-12', 7, 127, 74, 31, 7, 2652.23, 3.84),
('2024-11-14', 7, 27, 20, 0, 0, 0.0, 1.05),
('2024-11-16', 7, 31, 22, 0, 0, 0.0, 1.15),
('2024-11-18', 7, 94, 72, 30, 7, 2578.47, 3.77),
('2024-11-20', 7, 137, 76, 30, 6, 1517.4, 3.98),
('2024-11-22', 7, 43, 24, 0, 0, 0.0, 1.27),
('2024-11-24', 14, 43, 31, 0, 0, 0.0, 1.63),
('2024-11-26', 14, 221, 172, 26, 6, 3207.47, 8.94),
('2024-11-28', 14, 193, 149, 27, 6, 2138.35, 7.73),
('2024-11-30', 14, 128, 97, 24, 5, 1476.93, 5.03),
('2024-12-02', 30, 311, 235, 18, 4, 1986.3, 12.2),
('2024-12-04', 30, 234, 177, 19, 4, 1970.73, 9.22),
('2024-12-06', 30, 93, 68, 0, 0, 0.0, 3.55),
('2024-12-08', 30, 212, 114, 14, 3, 790.27, 5.9),
('2024-12-10', 30, 69, 36, 0, 0, 0.0, 1.85);


-- ---------------------------------------------------------------------
-- Analysis: reactivation funnel by lapse depth  (Report SMS section)
-- ---------------------------------------------------------------------
SELECT
    churn_days,

    SUM(sent)      AS sent,
    SUM(delivered) AS delivered,
    ROUND(
        SUM(delivered) * 100.0
        / SUM(sent),
        1
    ) AS delivery_pct,

    SUM(reactivated_7d) AS reactivated,
    ROUND(
        SUM(reactivated_7d) * 100.0
        / SUM(delivered),
        1
    ) AS reactivation_pct,

    SUM(pay_users_7d) AS pay_users,
    ROUND(
        SUM(pay_users_7d) * 100.0
        / NULLIF(SUM(reactivated_7d), 0),
        1
    ) AS pay_rate_of_reactivated_pct,

    SUM(pay_amount_7d) AS revenue,
    SUM(sms_cost)      AS sms_cost,
    ROUND(
        SUM(pay_amount_7d) * 1000.0
        / SUM(sent),
        0
    ) AS revenue_per_1k_sent

FROM sms_reactivation_log
GROUP BY churn_days
ORDER BY churn_days;
