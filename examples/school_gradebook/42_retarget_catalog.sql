-- Retarget gradebook datasets from the placeholder 'school' database
-- to 'demo_user' where the sample tables actually live.

UPDATE demo_user.DATASET
   SET DataBaseName = 'demo_user'
 WHERE DataBaseName = 'school';
