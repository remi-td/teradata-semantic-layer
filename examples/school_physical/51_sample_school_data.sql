-- =========================================================================
-- Minimal sample data for the gradebook scenario. ~40 fact rows is enough
-- to exercise filter predicates and cross-dataset joins.
-- =========================================================================

-- assessment-type hierarchy
INSERT INTO demo_user.gb_assessment_type VALUES ('HW_DAILY',    'HW', 'HW_DAILY',   'Daily homework',      0.050);
INSERT INTO demo_user.gb_assessment_type VALUES ('HW_WEEKLY',   'HW', 'HW_WEEKLY',  'Weekly problem set',  0.100);
INSERT INTO demo_user.gb_assessment_type VALUES ('QZ_SHORT',    'QZ', 'QZ_SHORT',   'Pop quiz',            0.050);
INSERT INTO demo_user.gb_assessment_type VALUES ('QZ_UNIT',     'QZ', 'QZ_UNIT',    'Unit quiz',           0.100);
INSERT INTO demo_user.gb_assessment_type VALUES ('EX_MIDTERM',  'EX', 'EX_MIDTERM', 'Midterm exam',        0.250);
INSERT INTO demo_user.gb_assessment_type VALUES ('EX_FINAL',    'EX', 'EX_FINAL',   'Final exam',          0.350);
INSERT INTO demo_user.gb_assessment_type VALUES ('PR_TEAM',     'PR', 'PR_TEAM',    'Team project',        0.150);
INSERT INTO demo_user.gb_assessment_type VALUES ('PR_INDIV',    'PR', 'PR_INDIV',   'Individual project',  0.150);

-- students (class_year: 1=freshman, 4=senior)
INSERT INTO demo_user.gb_student VALUES (1, 'Alex',   'Chen',       3, 'COMP_SCI');
INSERT INTO demo_user.gb_student VALUES (2, 'Jordan', 'Patel',      2, 'MATH');
INSERT INTO demo_user.gb_student VALUES (3, 'Taylor', 'Oduya',      4, 'PHYSICS');
INSERT INTO demo_user.gb_student VALUES (4, 'Morgan', 'Lindqvist',  1, 'COMP_SCI');
INSERT INTO demo_user.gb_student VALUES (5, 'Casey',  'Ramirez',    3, 'MATH');

-- courses
INSERT INTO demo_user.gb_course VALUES (101, 'CS-201', 'Algorithms',          'COMP_SCI', 4);
INSERT INTO demo_user.gb_course VALUES (102, 'CS-301', 'Operating Systems',   'COMP_SCI', 4);
INSERT INTO demo_user.gb_course VALUES (201, 'MA-214', 'Linear Algebra',      'MATH',     3);
INSERT INTO demo_user.gb_course VALUES (301, 'PH-220', 'Classical Mechanics', 'PHYSICS',  4);

-- assessments — mix of types across students and courses
INSERT INTO demo_user.gb_assessment VALUES ( 1, 1, 101, 'HW_DAILY',    8.5, 10.0, DATE '2026-01-15');
INSERT INTO demo_user.gb_assessment VALUES ( 2, 1, 101, 'HW_WEEKLY',  88.0, 100.0, DATE '2026-01-22');
INSERT INTO demo_user.gb_assessment VALUES ( 3, 1, 101, 'QZ_UNIT',    78.0, 100.0, DATE '2026-02-01');
INSERT INTO demo_user.gb_assessment VALUES ( 4, 1, 101, 'EX_MIDTERM', 82.0, 100.0, DATE '2026-02-20');
INSERT INTO demo_user.gb_assessment VALUES ( 5, 1, 101, 'EX_FINAL',   91.0, 100.0, DATE '2026-04-15');
INSERT INTO demo_user.gb_assessment VALUES ( 6, 1, 102, 'HW_WEEKLY',  92.0, 100.0, DATE '2026-01-29');
INSERT INTO demo_user.gb_assessment VALUES ( 7, 1, 102, 'EX_MIDTERM', 76.0, 100.0, DATE '2026-02-28');
INSERT INTO demo_user.gb_assessment VALUES ( 8, 1, 102, 'EX_FINAL',   84.0, 100.0, DATE '2026-04-20');

INSERT INTO demo_user.gb_assessment VALUES ( 9, 2, 201, 'HW_DAILY',    9.0, 10.0, DATE '2026-01-14');
INSERT INTO demo_user.gb_assessment VALUES (10, 2, 201, 'HW_WEEKLY',  95.0, 100.0, DATE '2026-01-21');
INSERT INTO demo_user.gb_assessment VALUES (11, 2, 201, 'QZ_SHORT',   85.0, 100.0, DATE '2026-02-03');
INSERT INTO demo_user.gb_assessment VALUES (12, 2, 201, 'EX_MIDTERM', 88.0, 100.0, DATE '2026-02-18');
INSERT INTO demo_user.gb_assessment VALUES (13, 2, 201, 'EX_FINAL',   94.0, 100.0, DATE '2026-04-10');
INSERT INTO demo_user.gb_assessment VALUES (14, 2, 101, 'HW_DAILY',    7.5, 10.0, DATE '2026-01-15');
INSERT INTO demo_user.gb_assessment VALUES (15, 2, 101, 'EX_MIDTERM', 72.0, 100.0, DATE '2026-02-20');
INSERT INTO demo_user.gb_assessment VALUES (16, 2, 101, 'EX_FINAL',   79.0, 100.0, DATE '2026-04-15');

INSERT INTO demo_user.gb_assessment VALUES (17, 3, 301, 'HW_WEEKLY',  80.0, 100.0, DATE '2026-01-25');
INSERT INTO demo_user.gb_assessment VALUES (18, 3, 301, 'QZ_UNIT',    74.0, 100.0, DATE '2026-02-05');
INSERT INTO demo_user.gb_assessment VALUES (19, 3, 301, 'EX_MIDTERM', 68.0, 100.0, DATE '2026-02-25');
INSERT INTO demo_user.gb_assessment VALUES (20, 3, 301, 'EX_FINAL',   73.0, 100.0, DATE '2026-04-18');
INSERT INTO demo_user.gb_assessment VALUES (21, 3, 301, 'PR_INDIV',   90.0, 100.0, DATE '2026-03-30');

INSERT INTO demo_user.gb_assessment VALUES (22, 4, 101, 'HW_DAILY',    6.5, 10.0, DATE '2026-01-15');
INSERT INTO demo_user.gb_assessment VALUES (23, 4, 101, 'HW_WEEKLY',  70.0, 100.0, DATE '2026-01-22');
INSERT INTO demo_user.gb_assessment VALUES (24, 4, 101, 'QZ_UNIT',    62.0, 100.0, DATE '2026-02-01');
INSERT INTO demo_user.gb_assessment VALUES (25, 4, 101, 'EX_MIDTERM', 58.0, 100.0, DATE '2026-02-20');
INSERT INTO demo_user.gb_assessment VALUES (26, 4, 101, 'EX_FINAL',   65.0, 100.0, DATE '2026-04-15');
INSERT INTO demo_user.gb_assessment VALUES (27, 4, 102, 'HW_WEEKLY',  72.0, 100.0, DATE '2026-01-29');
INSERT INTO demo_user.gb_assessment VALUES (28, 4, 102, 'EX_MIDTERM', 60.0, 100.0, DATE '2026-02-28');
INSERT INTO demo_user.gb_assessment VALUES (29, 4, 102, 'EX_FINAL',   68.0, 100.0, DATE '2026-04-20');
INSERT INTO demo_user.gb_assessment VALUES (30, 4, 102, 'PR_TEAM',    85.0, 100.0, DATE '2026-03-15');

INSERT INTO demo_user.gb_assessment VALUES (31, 5, 201, 'HW_DAILY',    9.5, 10.0, DATE '2026-01-14');
INSERT INTO demo_user.gb_assessment VALUES (32, 5, 201, 'HW_WEEKLY',  93.0, 100.0, DATE '2026-01-21');
INSERT INTO demo_user.gb_assessment VALUES (33, 5, 201, 'EX_MIDTERM', 90.0, 100.0, DATE '2026-02-18');
INSERT INTO demo_user.gb_assessment VALUES (34, 5, 201, 'EX_FINAL',   92.0, 100.0, DATE '2026-04-10');
INSERT INTO demo_user.gb_assessment VALUES (35, 5, 201, 'PR_TEAM',    88.0, 100.0, DATE '2026-03-20');
