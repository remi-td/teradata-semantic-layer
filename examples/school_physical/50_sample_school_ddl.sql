-- =========================================================================
-- Sample school-gradebook physical tables in demo_user.
--
-- These back the `school_gradebook` semantic model, which demonstrates
-- base-metric + filtered-rollup metrics (Phase 1) and field hierarchy
-- metadata (Phase 3). All identifiers are deliberately generic so the
-- scenario can be reused as a teaching example.
-- =========================================================================

-- ---------------- dimensions ----------------

CREATE MULTISET TABLE demo_user.gb_student, FALLBACK (
    student_id     INTEGER NOT NULL,
    first_name     VARCHAR(50) CHARACTER SET LATIN NOT CASESPECIFIC,
    last_name      VARCHAR(50) CHARACTER SET LATIN NOT CASESPECIFIC,
    class_year     SMALLINT,                        -- 1..4
    major          VARCHAR(30) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (student_id);

CREATE MULTISET TABLE demo_user.gb_course, FALLBACK (
    course_id      INTEGER NOT NULL,
    course_code    VARCHAR(12) CHARACTER SET LATIN NOT CASESPECIFIC,
    course_title   VARCHAR(100) CHARACTER SET LATIN NOT CASESPECIFIC,
    subject        VARCHAR(30) CHARACTER SET LATIN NOT CASESPECIFIC,
    credits        SMALLINT
) UNIQUE PRIMARY INDEX (course_id);

-- Assessment-type hierarchy: LVL1 in {HW, QZ, EX, PR}; LVL2 finer.
CREATE MULTISET TABLE demo_user.gb_assessment_type, FALLBACK (
    type_code       VARCHAR(12) CHARACTER SET LATIN NOT CASESPECIFIC NOT NULL,
    category_lvl1   VARCHAR(4)  CHARACTER SET LATIN NOT CASESPECIFIC,
    category_lvl2   VARCHAR(16) CHARACTER SET LATIN NOT CASESPECIFIC,
    display_name    VARCHAR(50) CHARACTER SET LATIN NOT CASESPECIFIC,
    default_weight  DECIMAL(5,3)
) UNIQUE PRIMARY INDEX (type_code);

-- ---------------- fact ----------------

CREATE MULTISET TABLE demo_user.gb_assessment, FALLBACK (
    assessment_id  INTEGER NOT NULL,
    student_id     INTEGER NOT NULL,
    course_id      INTEGER NOT NULL,
    type_code      VARCHAR(12) CHARACTER SET LATIN NOT CASESPECIFIC NOT NULL,
    score          DECIMAL(6,2),        -- raw score awarded
    max_score      DECIMAL(6,2),        -- scale (e.g. 100)
    graded_date    DATE
) UNIQUE PRIMARY INDEX (assessment_id)
INDEX ix_gb_assess_student (student_id)
INDEX ix_gb_assess_course (course_id)
INDEX ix_gb_assess_type (type_code);
