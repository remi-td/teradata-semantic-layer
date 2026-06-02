-- =========================================================================
-- Scenario D — School Gradebook (demonstrates Phase 1 + Phase 3 features).
-- Model name: school_gradebook
--
-- Purpose: show the "one base measure + many filtered rollups" pattern.
-- The base metric `score_avg = AVG(gb_assessment.score)` is defined once;
-- KPIs like `exam_score_avg`, `final_exam_score_avg`, and
-- `senior_exam_score_avg` reuse it via METRIC_FILTER rows.
--
-- Also registers a FIELD_HIERARCHY for the assessment-category levels
-- (category_lvl1 rolls up to category_lvl2). This is metadata only — it
-- does not change compiled SQL; agents and the GUI use it for drill-up/
-- drill-down navigation.
-- =========================================================================

-- ---------- 1. Model ----------
INSERT INTO demo_user.SEMANTIC_MODEL (model_name, description, owner_user, owner_group)
VALUES (
    'school_gradebook',
    'Course-grade analytics over student assessments. Fact = gb_assessment; dims = gb_student, gb_course, gb_assessment_type. Exercises base-metric + filtered variants and a two-level category hierarchy.',
    'DEMO_USER',
    'semantic-layer-team'
);

-- ---------- 2. Datasets + MODEL_DATASET links ----------
INSERT INTO demo_user.DATASET (dataset_name, description, granularity_desc, DataBaseName, TableName)
VALUES ('assessment', 'Graded assessment events (fact).', 'One row per graded item per student.', 'school', 'gb_assessment');

INSERT INTO demo_user.DATASET (dataset_name, description, granularity_desc, DataBaseName, TableName)
VALUES ('student', 'Enrolled students.', 'One row per student.', 'school', 'gb_student');

INSERT INTO demo_user.DATASET (dataset_name, description, granularity_desc, DataBaseName, TableName)
VALUES ('course', 'Catalog of courses.', 'One row per course.', 'school', 'gb_course');

INSERT INTO demo_user.DATASET (dataset_name, description, granularity_desc, DataBaseName, TableName)
VALUES ('assessment_type', 'Assessment-category hierarchy.', 'One row per type code.', 'school', 'gb_assessment_type');

-- Link all datasets to the school_gradebook model
INSERT INTO demo_user.MODEL_DATASET (model_id, dataset_id, is_primary)
SELECT m.model_id, d.dataset_id, CASE WHEN d.dataset_name='assessment' THEN 1 ELSE 0 END
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='school_gradebook'
  AND d.dataset_name IN ('assessment','student','course','assessment_type');

-- ---------- 3. Fields ----------
-- assessment (fact)
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'assessment_id', 'K', 'assessment_id', 'INTEGER', 0, 0, 'Assessment ID', 'Surrogate PK.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'student_id', 'K', 'student_id', 'INTEGER', 0, 0, 'Student ID', 'FK to student.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'course_id', 'K', 'course_id', 'INTEGER', 0, 0, 'Course ID', 'FK to course.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'type_code', 'K', 'type_code', 'VARCHAR(12)', 1, 0, 'Assessment Type Code', 'FK to assessment_type.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'score', 'A', 'score', 'DECIMAL(6,2)', 0, 0, 'Score', 'Raw score awarded.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'max_score', 'A', 'max_score', 'DECIMAL(6,2)', 0, 0, 'Max Score', 'Scale the score is out of.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'graded_date', 'A', 'graded_date', 'DATE', 1, 1, 'Graded Date', 'When the assessment was graded.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment';

-- student
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'student_id', 'K', 'student_id', 'INTEGER', 0, 0, 'Student ID', 'PK.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='student';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'class_year', 'A', 'class_year', 'SMALLINT', 1, 0, 'Class Year', '1=freshman through 4=senior.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='student';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'major', 'A', 'major', 'VARCHAR(30)', 1, 0, 'Major', 'Declared major.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='student';

-- course
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'course_id', 'K', 'course_id', 'INTEGER', 0, 0, 'Course ID', 'PK.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='course';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'subject', 'A', 'subject', 'VARCHAR(30)', 1, 0, 'Subject', 'Academic subject.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='course';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'course_code', 'A', 'course_code', 'VARCHAR(12)', 1, 0, 'Course Code', 'Short course code.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='course';

-- assessment_type (hierarchy dim)
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'type_code', 'K', 'type_code', 'VARCHAR(12)', 1, 0, 'Type Code', 'PK: canonical code.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment_type';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'category_lvl1', 'A', 'category_lvl1', 'VARCHAR(4)', 1, 0, 'Category (L1)', 'Top-level category: HW=Homework, QZ=Quiz, EX=Exam, PR=Project.'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment_type';
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, data_type, is_dimension, is_time_dimension, label, description)
SELECT d.dataset_id, 'category_lvl2', 'A', 'category_lvl2', 'VARCHAR(16)', 1, 0, 'Category (L2)', 'Fine-grained category (e.g. HW_DAILY, EX_FINAL).'
  FROM demo_user.DATASET d JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment_type';

-- ---------- 4. Dataset keys ----------
INSERT INTO demo_user.DATASET_KEY (dataset_id, field_id, key_type, key_ordinal, column_position)
SELECT d.dataset_id, f.field_id, 'PK', 1, 1
  FROM demo_user.DATASET d
  JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment' AND f.field_name='assessment_id';
INSERT INTO demo_user.DATASET_KEY (dataset_id, field_id, key_type, key_ordinal, column_position)
SELECT d.dataset_id, f.field_id, 'PK', 1, 1
  FROM demo_user.DATASET d
  JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='student' AND f.field_name='student_id';
INSERT INTO demo_user.DATASET_KEY (dataset_id, field_id, key_type, key_ordinal, column_position)
SELECT d.dataset_id, f.field_id, 'PK', 1, 1
  FROM demo_user.DATASET d
  JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='course' AND f.field_name='course_id';
INSERT INTO demo_user.DATASET_KEY (dataset_id, field_id, key_type, key_ordinal, column_position)
SELECT d.dataset_id, f.field_id, 'PK', 1, 1
  FROM demo_user.DATASET d
  JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
 WHERE m.model_name='school_gradebook' AND d.dataset_name='assessment_type' AND f.field_name='type_code';

-- ---------- 5. Relationships ----------
-- assessment → student
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT da.dataset_id, ds.dataset_id, 'assessment_to_student',
       'Each assessment belongs to one student.', 'MANY_TO_ONE', 'INNER'
  FROM demo_user.DATASET da
  JOIN demo_user.SEMANTIC_MODEL m ON da.model_id=m.model_id
  JOIN demo_user.DATASET ds ON ds.model_id=m.model_id AND ds.dataset_name='student'
 WHERE m.model_name='school_gradebook' AND da.dataset_name='assessment';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
  FROM demo_user.RELATIONSHIP r
  JOIN demo_user.DATASET df ON df.dataset_id=r.from_dataset_id
  JOIN demo_user.DATASET dt ON dt.dataset_id=r.to_dataset_id
  JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='student_id'
  JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='student_id'
 WHERE r.relationship_name='assessment_to_student';

-- assessment → course
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT da.dataset_id, dc.dataset_id, 'assessment_to_course',
       'Each assessment is for one course.', 'MANY_TO_ONE', 'INNER'
  FROM demo_user.DATASET da
  JOIN demo_user.SEMANTIC_MODEL m ON da.model_id=m.model_id
  JOIN demo_user.DATASET dc ON dc.model_id=m.model_id AND dc.dataset_name='course'
 WHERE m.model_name='school_gradebook' AND da.dataset_name='assessment';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
  FROM demo_user.RELATIONSHIP r
  JOIN demo_user.DATASET df ON df.dataset_id=r.from_dataset_id
  JOIN demo_user.DATASET dt ON dt.dataset_id=r.to_dataset_id
  JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='course_id'
  JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='course_id'
 WHERE r.relationship_name='assessment_to_course';

-- assessment → assessment_type
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT da.dataset_id, dat.dataset_id, 'assessment_to_type',
       'Each assessment has a category type.', 'MANY_TO_ONE', 'INNER'
  FROM demo_user.DATASET da
  JOIN demo_user.SEMANTIC_MODEL m ON da.model_id=m.model_id
  JOIN demo_user.DATASET dat ON dat.model_id=m.model_id AND dat.dataset_name='assessment_type'
 WHERE m.model_name='school_gradebook' AND da.dataset_name='assessment';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
  FROM demo_user.RELATIONSHIP r
  JOIN demo_user.DATASET df ON df.dataset_id=r.from_dataset_id
  JOIN demo_user.DATASET dt ON dt.dataset_id=r.to_dataset_id
  JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='type_code'
  JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='type_code'
 WHERE r.relationship_name='assessment_to_type';

-- ---------- 6. Base metrics (aggregate_fn + aggregate_arg populated) ----------
-- These are the raw measures that filtered variants reuse.
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id,
                               metric_type, is_additive, is_certified,
                               aggregate_fn, aggregate_arg)
SELECT m.model_id, 'score_avg',
       'Average raw score across all assessments.',
       d.dataset_id, 'SIMPLE', 0, 1,
       'AVG', 'assessment.score'
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'AVG(assessment.score)'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND mt.metric_name='score_avg';
INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'AVG(assessment.score)'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND mt.metric_name='score_avg';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='score'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='score_avg';

-- assessment_count base: COUNT(*) equivalent expressed as COUNT(assessment_id).
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id,
                               metric_type, is_additive, is_certified,
                               aggregate_fn, aggregate_arg)
SELECT m.model_id, 'assessment_count',
       'Number of graded assessments.',
       d.dataset_id, 'SIMPLE', 1, 1,
       'COUNT', 'assessment.assessment_id'
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(assessment.assessment_id)'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND mt.metric_name='assessment_count';
INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(assessment.assessment_id)'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
 WHERE m.model_name='school_gradebook' AND mt.metric_name='assessment_count';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='assessment_id'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='assessment_count';

-- ---------- 7. Filtered variants (base_metric_id + METRIC_FILTER) ----------
-- exam_score_avg = score_avg filtered by assessment_type.category_lvl1 = 'EX'
INSERT INTO demo_user.METRIC (model_id, metric_name, description,
                               primary_dataset_id, metric_type, is_additive, is_certified,
                               base_metric_id)
SELECT m.model_id, 'exam_score_avg',
       'Average score on exams only (category_lvl1 = EX). Compiler wraps score_avg with a CASE-WHEN filter.',
       NULL, 'SIMPLE', 0, 1,
       bm.metric_id
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.METRIC bm ON bm.model_id=m.model_id AND bm.metric_name='score_avg'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 1, f.field_id, '=', '''EX'''
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl1'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='exam_score_avg';

-- homework_score_avg = score_avg filtered by category_lvl1 = 'HW'
INSERT INTO demo_user.METRIC (model_id, metric_name, description,
                               primary_dataset_id, metric_type, is_additive, is_certified,
                               base_metric_id)
SELECT m.model_id, 'homework_score_avg',
       'Average score on homework only (category_lvl1 = HW).',
       NULL, 'SIMPLE', 0, 1,
       bm.metric_id
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.METRIC bm ON bm.model_id=m.model_id AND bm.metric_name='score_avg'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 1, f.field_id, '=', '''HW'''
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl1'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='homework_score_avg';

-- final_exam_score_avg = score_avg filtered by category_lvl2 = 'EX_FINAL' (LVL2 implies LVL1)
INSERT INTO demo_user.METRIC (model_id, metric_name, description,
                               primary_dataset_id, metric_type, is_additive, is_certified,
                               base_metric_id)
SELECT m.model_id, 'final_exam_score_avg',
       'Average score on final exams only (category_lvl2 = EX_FINAL).',
       NULL, 'SIMPLE', 0, 1,
       bm.metric_id
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.METRIC bm ON bm.model_id=m.model_id AND bm.metric_name='score_avg'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 1, f.field_id, '=', '''EX_FINAL'''
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl2'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='final_exam_score_avg';

-- senior_exam_score_avg = score_avg filtered by category_lvl1='EX' AND student.class_year=4.
-- This demonstrates a composite filter that spans TWO datasets: the compiler
-- auto-joins both filter-field datasets into the FROM clause.
INSERT INTO demo_user.METRIC (model_id, metric_name, description,
                               primary_dataset_id, metric_type, is_additive, is_certified,
                               base_metric_id)
SELECT m.model_id, 'senior_exam_score_avg',
       'Average exam score among senior students (class_year=4 AND category_lvl1=EX).',
       NULL, 'SIMPLE', 0, 1,
       bm.metric_id
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.METRIC bm ON bm.model_id=m.model_id AND bm.metric_name='score_avg'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 1, f.field_id, '=', '''EX'''
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl1'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='senior_exam_score_avg';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 2, f.field_id, '=', '4'
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='student'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='class_year'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='senior_exam_score_avg';

-- exam_count = assessment_count filtered by category_lvl1='EX'  (COUNT aggregate test)
INSERT INTO demo_user.METRIC (model_id, metric_name, description,
                               primary_dataset_id, metric_type, is_additive, is_certified,
                               base_metric_id)
SELECT m.model_id, 'exam_count',
       'Number of graded exam assessments.',
       NULL, 'SIMPLE', 1, 1,
       bm.metric_id
  FROM demo_user.SEMANTIC_MODEL m
  JOIN demo_user.METRIC bm ON bm.model_id=m.model_id AND bm.metric_name='assessment_count'
 WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
SELECT mt.metric_id, 1, f.field_id, '=', '''EX'''
  FROM demo_user.METRIC mt
  JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl1'
 WHERE m.model_name='school_gradebook' AND mt.metric_name='exam_count';

-- ---------- 8. Field hierarchy (Phase 3 — metadata only) ----------
INSERT INTO demo_user.FIELD_HIERARCHY (model_id, hierarchy_name, description)
SELECT m.model_id, 'assessment_category',
       'Two-level rollup of assessment types: category_lvl1 (HW/QZ/EX/PR) → category_lvl2 (specific).'
  FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='school_gradebook';

INSERT INTO demo_user.FIELD_HIERARCHY_LEVEL (hierarchy_id, level_ord, field_id, level_name)
SELECT h.hierarchy_id, 1, f.field_id, 'Category'
  FROM demo_user.FIELD_HIERARCHY h
  JOIN demo_user.SEMANTIC_MODEL m ON h.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl1'
 WHERE m.model_name='school_gradebook' AND h.hierarchy_name='assessment_category';

INSERT INTO demo_user.FIELD_HIERARCHY_LEVEL (hierarchy_id, level_ord, field_id, level_name)
SELECT h.hierarchy_id, 2, f.field_id, 'Sub-category'
  FROM demo_user.FIELD_HIERARCHY h
  JOIN demo_user.SEMANTIC_MODEL m ON h.model_id=m.model_id
  JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='assessment_type'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='category_lvl2'
 WHERE m.model_name='school_gradebook' AND h.hierarchy_name='assessment_category';

