-- Drop the shared physical gradebook sample tables. Run this after every
-- catalog scenario that depends on this data has been uninstalled.

DROP TABLE demo_user.gb_assessment;
DROP TABLE demo_user.gb_course;
DROP TABLE demo_user.gb_student;
DROP TABLE demo_user.gb_assessment_type;
