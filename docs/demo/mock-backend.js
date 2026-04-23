/* Teradata Semantic Catalog — demo mock backend.
 *
 * The static GUI (`app.js`) calls `window.fetch` for every REST round
 * trip. This script intercepts those calls BEFORE app.js loads and
 * answers them from a single in-memory model of `school_gradebook`.
 * The canned payloads are the exact shapes the real FastAPI endpoints
 * return; the intention is that you get the real UX without a DB.
 *
 * What works:
 *   GET  /api/health
 *   GET  /api/ping
 *   GET  /api/models
 *   GET  /api/models/<m>/tree
 *   GET  /api/models/<m>/graph
 *   GET  /api/describe?entity_type=...&entity_name=...
 *   GET  /api/search?q=...
 *   POST /api/query/compile
 *   POST /api/query/execute
 *   POST /api/query/explain
 *   GET  /api/import/template
 *   POST /api/import          (replies with a friendly "demo" error)
 *   GET  /api/export/osi/<m>
 *
 * Everything else returns 404.
 */
(function () {
  'use strict';

  // ---------------------------------------------- The one demo model

  const MODEL = 'school_gradebook';

  const MODELS = [{
    model_id: 1, model_name: MODEL,
    description: 'Course-grade analytics. Base metric + filtered rollups.',
    dataset_count: 4, metric_count: 4, view_count: 1,
  }];

  const DATASETS = [
    { id: 10, name: 'assessment', db: 'school', table: 'gb_assessment',
      desc: 'Graded assessment events (fact). One row per graded item per student.',
      sub: 'TABLE', fields: [
        { name: 'assessment_id', type: 'K', dt: 'INTEGER',      dim: false, time: false, desc: 'Surrogate PK.' },
        { name: 'student_id',    type: 'K', dt: 'INTEGER',      dim: false, time: false, desc: 'FK to student.' },
        { name: 'course_id',     type: 'K', dt: 'INTEGER',      dim: false, time: false, desc: 'FK to course.' },
        { name: 'type_code',     type: 'K', dt: 'VARCHAR(12)',  dim: true,  time: false, desc: 'FK to assessment_type.' },
        { name: 'score',         type: 'A', dt: 'DECIMAL(6,2)', dim: false, time: false, desc: 'Raw score awarded.' },
        { name: 'max_score',     type: 'A', dt: 'DECIMAL(6,2)', dim: false, time: false, desc: 'Scale the score is out of.' },
        { name: 'graded_date',   type: 'A', dt: 'DATE',         dim: true,  time: true,  desc: 'When the assessment was graded.' },
      ]},
    { id: 11, name: 'student', db: 'school', table: 'gb_student',
      desc: 'Enrolled students.', sub: 'TABLE', fields: [
        { name: 'student_id',   type: 'K', dt: 'INTEGER',     dim: false, time: false, desc: 'PK.' },
        { name: 'full_name',    type: 'A', dt: 'VARCHAR(120)',dim: true,  time: false, desc: 'Printable name.' },
        { name: 'year_group',   type: 'A', dt: 'VARCHAR(24)', dim: true,  time: false, desc: 'Senior / junior / etc.' },
      ]},
    { id: 12, name: 'course', db: 'school', table: 'gb_course',
      desc: 'Catalog of courses.', sub: 'TABLE', fields: [
        { name: 'course_id',    type: 'K', dt: 'INTEGER',     dim: false, time: false, desc: 'PK.' },
        { name: 'course_name',  type: 'A', dt: 'VARCHAR(80)', dim: true,  time: false, desc: 'Course title.' },
        { name: 'department',   type: 'A', dt: 'VARCHAR(40)', dim: true,  time: false, desc: 'Math / Science / …' },
      ]},
    { id: 13, name: 'assessment_type', db: 'school', table: 'gb_assessment_type',
      desc: 'Assessment-category hierarchy.', sub: 'TABLE', fields: [
        { name: 'type_code',       type: 'K', dt: 'VARCHAR(12)', dim: false, time: false, desc: 'PK.' },
        { name: 'category_lvl1',   type: 'A', dt: 'VARCHAR(24)', dim: true,  time: false, desc: 'EX (exam), HW (homework), PR (project).' },
        { name: 'category_lvl2',   type: 'A', dt: 'VARCHAR(24)', dim: true,  time: false, desc: 'Final exam / midterm / weekly HW …' },
      ]},
  ];

  const METRICS = [
    { id: 100, name: 'score_avg',
      desc: 'Base metric — average of awarded score. Every KPI below filters this one.',
      type: 'SIMPLE', agg: 'AVG', arg: 'assessment.score',
      certified: true, ds: 'assessment',
      expr_teradata: 'AVG(assessment.score)',
      ai: 'Use as the default academic-performance measure. Filter by assessment category for specific KPIs.',
      synonyms: ['grade average', 'average score'] },
    { id: 101, name: 'exam_score_avg',
      desc: 'Average score on any exam (filtered variant of score_avg).',
      type: 'SIMPLE', agg: 'AVG', arg: 'assessment.score',
      certified: true, ds: 'assessment',
      base_metric: 'score_avg',
      filters: [{ field: 'assessment_type.category_lvl1', op: '=', value: "'EX'" }],
      expr_teradata: 'AVG(CASE WHEN assessment_type.category_lvl1 = \'EX\' THEN assessment.score END)',
      ai: 'All exams, any year. For final exams only use final_exam_score_avg.',
      synonyms: ['exam average'] },
    { id: 102, name: 'final_exam_score_avg',
      desc: 'Average score on final exams only (filtered rollup).',
      type: 'SIMPLE', agg: 'AVG', arg: 'assessment.score',
      certified: true, ds: 'assessment',
      base_metric: 'score_avg',
      filters: [
        { field: 'assessment_type.category_lvl1', op: '=', value: "'EX'" },
        { field: 'assessment_type.category_lvl2', op: '=', value: "'FINAL'" }
      ],
      expr_teradata: "AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' AND assessment_type.category_lvl2 = 'FINAL' THEN assessment.score END)",
      synonyms: ['final average', 'finals avg'] },
    { id: 103, name: 'assessment_count',
      desc: 'How many graded items were recorded.', type: 'SIMPLE', agg: 'COUNT',
      arg: 'assessment.assessment_id', certified: false, ds: 'assessment',
      expr_teradata: 'COUNT(assessment.assessment_id)' },
  ];

  const RELATIONSHIPS = [
    { id: 200, name: 'assessment_to_student',   from: 'assessment', to: 'student',         card: 'MANY_TO_ONE', cols: [['student_id','student_id']] },
    { id: 201, name: 'assessment_to_course',    from: 'assessment', to: 'course',          card: 'MANY_TO_ONE', cols: [['course_id','course_id']] },
    { id: 202, name: 'assessment_to_type',      from: 'assessment', to: 'assessment_type', card: 'MANY_TO_ONE', cols: [['type_code','type_code']] },
  ];

  const VIEWS = [
    { id: 300, name: 'grade_dashboard',
      desc: 'Certified projection for the student-progress dashboard.',
      pk_dataset: 'assessment', certified: true, pub: true,
      members: ['score_avg', 'exam_score_avg', 'final_exam_score_avg',
                'student.full_name', 'course.course_name',
                'assessment_type.category_lvl1', 'assessment.graded_date'] },
  ];

  const AI_MODEL = "School gradebook analytics — one fact table (assessment), three dims (student, course, assessment_type), a base metric score_avg with filtered variants for specific assessment categories.";

  // ---------------------------------------------- Response builders

  function modelsResp() { return MODELS; }

  function healthResp() { return { status: 'ok', version: '0.4.0', host: 'demo.localhost', database: 'demo_user' }; }
  function pingResp()   { return { ok: true, host: 'demo.localhost' }; }

  function treeResp() {
    return {
      model: { name: MODEL, description: MODELS[0].description },
      datasets: DATASETS.map(d => ({
        name: d.name, sub_kind: d.sub, description: d.desc,
        fields: d.fields.map(f => ({
          name: f.name, type: f.type, data_type: f.dt,
          is_dimension: !!f.dim, is_time_dimension: !!f.time,
        })),
      })),
      metrics: METRICS.map(m => ({
        name: m.name, description: m.desc, metric_type: m.type,
        primary_dataset: m.ds, is_certified: m.certified,
      })),
      views: VIEWS.map(v => ({
        name: v.name, description: v.desc,
        primary_dataset: v.pk_dataset, is_certified: v.certified,
      })),
      relationships: RELATIONSHIPS.map(r => ({
        name: r.name, from: r.from, to: r.to, cardinality: r.card,
      })),
    };
  }

  function graphResp() {
    const nodes = [];
    DATASETS.forEach(d => nodes.push({
      id: `ds:${d.id}`, label: d.name, kind: 'DATASET', sub_kind: d.sub,
      description: d.desc, meta: { display_name: d.name, field_count: d.fields.length },
    }));
    METRICS.forEach(m => nodes.push({
      id: `met:${m.id}`, label: m.name, kind: 'METRIC', sub_kind: m.type,
      description: m.desc, meta: { metric_type: m.type },
    }));
    VIEWS.forEach(v => nodes.push({
      id: `view:${v.id}`, label: v.name, kind: 'VIEW', sub_kind: 'VIEW',
      description: v.desc, meta: {},
    }));

    const edges = [];
    RELATIONSHIPS.forEach(r => {
      const from = DATASETS.find(d => d.name === r.from);
      const to = DATASETS.find(d => d.name === r.to);
      edges.push({
        id: `rel:${r.id}`, source: `ds:${from.id}`, target: `ds:${to.id}`,
        kind: 'RELATIONSHIP', label: r.name, cardinality: r.card, role_name: null,
      });
    });
    METRICS.forEach(m => {
      const ds = DATASETS.find(d => d.name === m.ds);
      if (ds) edges.push({
        id: `e-met:${m.id}-ds:${ds.id}`,
        source: `met:${m.id}`, target: `ds:${ds.id}`, kind: 'METRIC_OF',
      });
    });
    VIEWS.forEach(v => {
      const ds = DATASETS.find(d => d.name === v.pk_dataset);
      if (ds) edges.push({
        id: `e-view:${v.id}-ds:${ds.id}`,
        source: `view:${v.id}`, target: `ds:${ds.id}`, kind: 'VIEW_OF',
      });
    });

    return { model_name: MODEL, nodes, edges };
  }

  function describeResp(kind, name) {
    const attrs = [];
    let found = null;
    if (kind === 'DATASET') {
      const d = DATASETS.find(x => x.name === name);
      if (d) {
        found = d;
        attrs.push({ attr_ordinal: 1, attr_key: 'entity_type', attr_value: 'DATASET' });
        attrs.push({ attr_ordinal: 2, attr_key: 'name',        attr_value: d.name });
        attrs.push({ attr_ordinal: 3, attr_key: 'description', attr_value: d.desc });
        attrs.push({ attr_ordinal: 4, attr_key: 'source',      attr_value: `${d.db}.${d.table}` });
        d.fields.forEach((f, i) => {
          attrs.push({ attr_ordinal: 10 + i, attr_key: 'field',
                       attr_value: `${f.name} ${f.type} ${f.dt}${f.dim ? ' dim' : ''}${f.time ? ' time' : ''}` });
        });
      }
    } else if (kind === 'METRIC') {
      const m = METRICS.find(x => x.name === name);
      if (m) {
        found = m;
        attrs.push({ attr_ordinal: 1, attr_key: 'entity_type',  attr_value: 'METRIC' });
        attrs.push({ attr_ordinal: 2, attr_key: 'name',         attr_value: m.name });
        attrs.push({ attr_ordinal: 3, attr_key: 'description',  attr_value: m.desc });
        attrs.push({ attr_ordinal: 4, attr_key: 'metric_type',  attr_value: m.type });
        attrs.push({ attr_ordinal: 5, attr_key: 'primary_dataset', attr_value: m.ds });
        attrs.push({ attr_ordinal: 6, attr_key: 'aggregate',    attr_value: `${m.agg}(${m.arg})` });
        attrs.push({ attr_ordinal: 10, attr_key: 'expr_teradata', attr_value: m.expr_teradata });
        if (m.base_metric) attrs.push({ attr_ordinal: 11, attr_key: 'base_metric', attr_value: m.base_metric });
        if (m.filters) m.filters.forEach((f, i) => {
          attrs.push({ attr_ordinal: 12 + i, attr_key: 'filter', attr_value: `${f.field} ${f.op} ${f.value}` });
        });
        if (m.ai)       attrs.push({ attr_ordinal: 30, attr_key: 'ai_instructions', attr_value: m.ai });
        if (m.synonyms) attrs.push({ attr_ordinal: 31, attr_key: 'ai_synonyms', attr_value: JSON.stringify(m.synonyms) });
      }
    } else if (kind === 'VIEW') {
      const v = VIEWS.find(x => x.name === name);
      if (v) {
        found = v;
        attrs.push({ attr_ordinal: 1, attr_key: 'entity_type', attr_value: 'VIEW' });
        attrs.push({ attr_ordinal: 2, attr_key: 'name', attr_value: v.name });
        attrs.push({ attr_ordinal: 3, attr_key: 'description', attr_value: v.desc });
        attrs.push({ attr_ordinal: 4, attr_key: 'primary_dataset', attr_value: v.pk_dataset });
        v.members.forEach((m, i) => {
          attrs.push({ attr_ordinal: 20 + i, attr_key: 'member', attr_value: m });
        });
      }
    }
    if (!found) return null;
    return { entity_type: kind, entity_name: name, model_name: MODEL, attributes: attrs };
  }

  function searchResp(q) {
    q = (q || '').toLowerCase().trim();
    if (!q) return [];
    const hits = [];
    DATASETS.forEach(d => {
      if (d.name.toLowerCase().includes(q) || d.desc.toLowerCase().includes(q)) {
        hits.push({ entity_type: 'DATASET', entity_name: d.name, parent_name: MODEL,
                    description: d.desc, synonyms: '', relevance: 80 });
      }
    });
    METRICS.forEach(m => {
      const score = [m.name, m.desc, (m.synonyms || []).join(',')].join(' ').toLowerCase();
      if (score.includes(q)) {
        hits.push({ entity_type: 'METRIC', entity_name: m.name, parent_name: MODEL,
                    description: m.desc, synonyms: (m.synonyms || []).join(', '), relevance: 95 });
      }
    });
    DATASETS.forEach(d => d.fields.forEach(f => {
      if (f.name.toLowerCase().includes(q) || (f.desc || '').toLowerCase().includes(q)) {
        hits.push({ entity_type: 'FIELD', entity_name: f.name, parent_name: d.name,
                    description: f.desc || '', synonyms: '', relevance: 60 });
      }
    }));
    VIEWS.forEach(v => {
      if (v.name.toLowerCase().includes(q) || v.desc.toLowerCase().includes(q)) {
        hits.push({ entity_type: 'VIEW', entity_name: v.name, parent_name: MODEL,
                    description: v.desc, synonyms: '', relevance: 70 });
      }
    });
    return hits.sort((a, b) => b.relevance - a.relevance);
  }

  // ---- compile ---------------------------------------------------

  function resolveMetric(name) { return METRICS.find(m => m.name === name); }
  function resolveField(ref) {
    // "dataset.field" or just "field"
    const m = ref.match(/^([a-z0-9_]+)\.([a-z0-9_]+)$/i);
    if (!m) return null;
    const ds = DATASETS.find(d => d.name === m[1]);
    if (!ds) return null;
    const f = ds.fields.find(x => x.name === m[2]);
    if (!f) return null;
    return { dataset: ds, field: f, alias: ds.name, ref: `${ds.name}.${f.name}` };
  }

  function pickAnchor(metrics) {
    const names = metrics.map(m => m && m.ds).filter(Boolean);
    const pri = names[0] || 'assessment';
    return DATASETS.find(d => d.name === pri) || DATASETS[0];
  }

  function requiredDatasets(metricObjs, dims, whereF) {
    const need = new Set();
    metricObjs.forEach(m => { if (m && m.ds) need.add(m.ds); });
    metricObjs.forEach(m => {
      if (m && m.filters) m.filters.forEach(f => {
        const ref = resolveField(f.field);
        if (ref) need.add(ref.dataset.name);
      });
    });
    (dims || []).forEach(d => { const r = resolveField(d); if (r) need.add(r.dataset.name); });
    (whereF || []).forEach(w => { const r = resolveField(w.field); if (r) need.add(r.dataset.name); });
    return Array.from(need);
  }

  function buildJoinPath(anchor, needs) {
    const present = new Set([anchor]);
    const steps = [`FROM school.gb_${anchor} AS ${anchor}`];
    const order = ['student', 'course', 'assessment_type'].filter(x => needs.includes(x));
    order.forEach(target => {
      if (present.has(target)) return;
      const rel = RELATIONSHIPS.find(r => r.from === anchor && r.to === target)
               || RELATIONSHIPS.find(r => r.from === target && r.to === anchor);
      if (!rel) return;
      const to = DATASETS.find(d => d.name === target);
      const fromF = rel.cols[0][0], toF = rel.cols[0][1];
      steps.push(`INNER JOIN ${to.db}.${to.table} AS ${target} ON ${rel.from}.${fromF} = ${rel.to}.${toF}`);
      present.add(target);
    });
    return steps;
  }

  function compilePlan(req) {
    const metrics = (req.metrics || []).map(resolveMetric).filter(Boolean);
    const unknown = (req.metrics || []).filter(n => !resolveMetric(n));
    if (unknown.length) return { code: 'UNKNOWN_METRIC', message: `Unknown metric: ${unknown[0]}` };

    const dims = (req.dimensions || []);
    const badDim = dims.find(d => !resolveField(d));
    if (badDim) return { code: 'UNKNOWN_FIELD', message: `Dim '${badDim}': field not found` };

    const whereF = (req.where || []);
    const badW = whereF.find(w => w.field && !resolveField(w.field));
    if (badW) return { code: 'UNKNOWN_FIELD', message: `WHERE '${badW.field}': field not found` };

    // Chasm check — if metrics span > 1 primary dataset, refuse.
    const grains = new Set(metrics.map(m => m.ds));
    if (grains.size > 1) {
      return { code: 'CHASM_TRAP',
               message: `CHASM_WARNING: metrics span ${grains.size} grains (${Array.from(grains).join(', ')}) — split the request by grain.` };
    }

    const anchor = pickAnchor(metrics);
    const needs = requiredDatasets(metrics, dims, whereF);
    const joined = Array.from(new Set(needs.filter(n => n !== anchor.name)));

    // SELECT parts
    const selects = [];
    dims.forEach(d => {
      const r = resolveField(d);
      selects.push(`${r.alias}.${r.field.name} AS ${r.field.name}`);
    });
    metrics.forEach(m => {
      selects.push(`${m.expr_teradata} AS ${m.name}`);
    });

    // JOIN path
    const fromParts = buildJoinPath(anchor.name, needs);

    // WHERE
    const whereParts = whereF.map(w => {
      const r = resolveField(w.field);
      const rhs = (w.type === 'STRING' || (!w.type && isNaN(+w.value)))
        ? `'${String(w.value || '').replace(/'/g, "''")}'`
        : String(w.value);
      return `${r.alias}.${r.field.name} ${w.op} ${rhs}`;
    });

    // HAVING
    const havingParts = (req.having || []).map(h => {
      const m = resolveMetric(h.metric);
      if (!m) return null;
      const rhs = isNaN(+h.value) ? `'${h.value}'` : h.value;
      return `(${m.expr_teradata}) ${h.op} ${rhs}`;
    }).filter(Boolean);

    // GROUP BY
    const needsGroupBy = metrics.length > 0 && dims.length > 0;
    const groupByParts = needsGroupBy ? dims.map(d => {
      const r = resolveField(d);
      return `${r.alias}.${r.field.name}`;
    }) : [];

    // DISTINCT (dims only)
    const distinct = dims.length > 0 && metrics.length === 0;

    // ORDER BY / limit
    const order = (req.sort || []).map(s => `${s.field} ${(s.direction || 'ASC').toUpperCase()}`);
    const limit = Number.isFinite(+req.limit) && +req.limit > 0 ? +req.limit : 0;

    let sql = 'LOCKING ROW FOR ACCESS\nSELECT';
    if (distinct) sql += ' DISTINCT';
    sql += '\n  ' + selects.join(',\n  ') + '\n';
    sql += fromParts.join('\n') + '\n';
    if (whereParts.length) sql += 'WHERE ' + whereParts.join('\n  AND ') + '\n';
    if (groupByParts.length) sql += 'GROUP BY\n  ' + groupByParts.join(',\n  ') + '\n';
    if (havingParts.length) sql += 'HAVING ' + havingParts.join('\n   AND ') + '\n';
    if (order.length) sql += 'ORDER BY ' + order.join(', ') + '\n';
    if (limit) sql = sql.replace('SELECT', `SELECT TOP ${limit}`);

    return {
      ok: true,
      sql: sql.trimEnd(),
      anchor: anchor.name,
      joined: joined,
    };
  }

  // Canned execution results — a few shapes for the most likely queries.
  function executeRows(req, sqlText) {
    const metrics = (req.metrics || []).map(resolveMetric).filter(Boolean);
    const dims = (req.dimensions || []);
    const cols = [];
    const rows = [];

    // Put dims then metrics.
    const dimNames = dims.map(d => { const r = resolveField(d); return r ? r.field.name : d; });
    cols.push(...dimNames);
    cols.push(...metrics.map(m => m.name));

    const preset = canonicalRows(req);
    if (preset) return { columns: cols, rows: preset, row_count: preset.length, truncated: false };

    // Fallback: deterministic fake rows
    if (dims.length === 0 && metrics.length) {
      rows.push(metrics.map(m => ({ score_avg: 81.4, exam_score_avg: 74.2, final_exam_score_avg: 68.9, assessment_count: 4820 })[m.name] || 0));
      return { columns: cols, rows, row_count: 1, truncated: false };
    }
    // Single-dim join: invent 3-5 rows
    if (dims.length) {
      const firstDim = resolveField(dims[0]);
      const dimValues = sampleDimValues(firstDim);
      dimValues.forEach((v, i) => {
        const row = [v];
        metrics.forEach(m => row.push(+(75 + (i * 3.7) + (m.name.length * 0.5)).toFixed(2)));
        rows.push(row);
      });
      return { columns: cols, rows, row_count: rows.length, truncated: false };
    }
    return { columns: cols, rows, row_count: 0, truncated: false };
  }

  function sampleDimValues(r) {
    if (!r) return ['A', 'B', 'C'];
    const fqn = `${r.dataset.name}.${r.field.name}`;
    return ({
      'assessment_type.category_lvl1': ['EX', 'HW', 'PR'],
      'assessment_type.category_lvl2': ['FINAL', 'MIDTERM', 'WEEKLY', 'PROJECT'],
      'student.year_group':            ['Senior', 'Junior', 'Sophomore', 'Freshman'],
      'course.department':             ['Math', 'Science', 'English', 'History'],
      'course.course_name':            ['Algebra II', 'AP Chemistry', 'World Lit', 'US History'],
    })[fqn] || ['Value A', 'Value B', 'Value C'];
  }

  // Golden-path cached results for the "recommended" demo queries.
  function canonicalRows(req) {
    const key = JSON.stringify({
      m: (req.metrics || []).slice().sort(),
      d: (req.dimensions || []).slice().sort(),
      w: (req.where || []).map(x => `${x.field}${x.op}${x.value}`).sort(),
    });
    const presets = {
      [JSON.stringify({m:['score_avg'], d:['assessment_type.category_lvl1'], w:[]})]:
        [['EX', 74.2], ['HW', 88.1], ['PR', 81.6]],
      [JSON.stringify({m:['score_avg','exam_score_avg','final_exam_score_avg'], d:['course.department'], w:[]})]:
        [
          ['English', 83.2, 76.1, 71.4],
          ['History', 80.9, 73.8, 69.6],
          ['Math',    77.6, 71.2, 64.9],
          ['Science', 79.8, 72.4, 67.1],
        ],
      [JSON.stringify({m:['exam_score_avg'], d:['student.year_group'], w:[]})]:
        [['Freshman', 71.8], ['Sophomore', 73.5], ['Junior', 75.6], ['Senior', 78.9]],
    };
    return presets[key];
  }

  function explainResp() {
    return { ok: true,
      plan: [
        "  1) First, we lock a distinct view-level READ lock for access on school.gb_assessment.",
        "  2) Next, we do a single-AMP STAT FUNCTION step from school.gb_assessment_type in view READ lock.",
        "  3) We join school.gb_assessment with school.gb_assessment_type using a hash join with a join condition of",
        "     (school.gb_assessment.type_code = school.gb_assessment_type.type_code).",
        "  4) We compute aggregate AVG(...) by grouping; results redistributed and sorted.",
        "  -> The result row is sent back to the user as the result of statement 1.",
      ].join('\n'),
      message: null,
    };
  }

  // ---- import / export -----------------------------------------

  function importTemplateResp() {
    return {
      yaml: [
        '# Minimal import example — paste and edit in the GUI',
        'model: school_gradebook',
        'metrics:',
        '  - name: my_new_metric',
        '    description: Example measure, copy me',
        '    primary_dataset: assessment',
        '    metric_type: SIMPLE',
        '    expressions:',
        '      TERADATA: "SUM(assessment.score)"',
        '      ANSI_SQL: "SUM(score)"',
        'ai_context:',
        '  - entity_type: METRIC',
        '    entity_name: my_new_metric',
        '    instructions: "Total points awarded across assessments."',
        '    synonyms: ["points"]',
        '',
      ].join('\n')
    };
  }

  function importRunResp(body) {
    // Friendly demo-mode response — we don't actually persist anything.
    return {
      model: body.model || MODEL,
      dry_run: !!body.dry_run,
      total: 1,
      ok_count: 0,
      error_count: 1,
      applied: false,
      results: [{
        ord: 1, kind: 'METRIC', name: (body.text || '').match(/name:\s*([\w-]+)/)?.[1] || '—',
        status: 'ERROR',
        message: 'This is the static demo — changes are not persisted. Install the catalog to apply imports.',
        entity_id: null,
      }],
    };
  }

  function osiExport() {
    return [
      'version: "0.1.1"',
      'semantic_model:',
      '  - name: school_gradebook',
      '    description: Course-grade analytics. Base metric + filtered rollups.',
      '    datasets:',
      '      - name: assessment',
      '        source: school.gb_assessment',
      '        primary_key: [assessment_id]',
      '        fields:',
      '          - name: assessment_id', '            data_type: INTEGER', '            key: true',
      '          - name: score',       '            data_type: DECIMAL(6,2)',
      '          - name: graded_date', '            data_type: DATE',
      '            dimension: { is_time: true }',
      '      - name: assessment_type',
      '        source: school.gb_assessment_type',
      '        primary_key: [type_code]',
      '        fields:',
      '          - name: category_lvl1', '            data_type: VARCHAR(24)',
      '            dimension: {}',
      '    relationships:',
      '      - name: assessment_to_type',
      '        from: assessment', '        to: assessment_type',
      '        from_columns: [type_code]', '        to_columns: [type_code]',
      '        cardinality: MANY_TO_ONE',
      '    metrics:',
      '      - name: score_avg',
      '        description: Base metric — average of awarded score.',
      '        expression:',
      '          dialects:',
      '            - dialect: TERADATA',
      '              expression: "AVG(assessment.score)"',
      '      - name: exam_score_avg',
      '        description: Average score on any exam.',
      '        expression:',
      '          dialects:',
      '            - dialect: TERADATA',
      '              expression: "AVG(CASE WHEN assessment_type.category_lvl1 = \'EX\' THEN assessment.score END)"',
      '    ai_context:',
      '      instructions: "' + AI_MODEL + '"',
    ].join('\n');
  }

  // ---------------------------------------------- Fetch interceptor

  const originalFetch = window.fetch.bind(window);

  function makeResponse(body, status = 200, contentType = 'application/json') {
    const text = (typeof body === 'string') ? body : JSON.stringify(body);
    return new Response(text, {
      status,
      headers: { 'Content-Type': contentType },
    });
  }

  async function route(url, init) {
    const method = (init && init.method) || 'GET';
    const u = new URL(url, 'http://demo/');
    const path = u.pathname;
    const qs = u.searchParams;

    // Health + models
    if (path === '/api/health' && method === 'GET') return makeResponse(healthResp());
    if (path === '/api/ping'   && method === 'GET') return makeResponse(pingResp());
    if (path === '/api/models' && method === 'GET') return makeResponse(modelsResp());

    // Tree / graph
    let m;
    if ((m = path.match(/^\/api\/models\/([^/]+)\/tree$/))) {
      if (decodeURIComponent(m[1]) !== MODEL) return makeResponse({detail: 'unknown model'}, 404);
      return makeResponse(treeResp());
    }
    if ((m = path.match(/^\/api\/models\/([^/]+)\/graph$/))) {
      if (decodeURIComponent(m[1]) !== MODEL) return makeResponse({detail: 'unknown model'}, 404);
      return makeResponse(graphResp());
    }

    // Describe / search
    if (path === '/api/describe' && method === 'GET') {
      const r = describeResp(qs.get('entity_type'), qs.get('entity_name'));
      return r ? makeResponse(r) : makeResponse({detail:'not found'}, 404);
    }
    if (path === '/api/search' && method === 'GET') {
      return makeResponse(searchResp(qs.get('q')));
    }

    // Query compile / execute / explain
    if (path === '/api/query/compile' && method === 'POST') {
      const body = init && init.body ? JSON.parse(init.body) : {};
      const plan = compilePlan(body);
      if (!plan.ok) {
        return makeResponse({
          compiled_sql: null, is_valid: 0,
          validation_message: `${plan.code}: ${plan.message}`,
          anchor_dataset: null, joined_datasets: null, execution: null,
        });
      }
      return makeResponse({
        compiled_sql: plan.sql, is_valid: 1,
        validation_message: null,
        anchor_dataset: plan.anchor, joined_datasets: plan.joined.join(', ') || null,
        execution: null,
      });
    }
    if (path === '/api/query/execute' && method === 'POST') {
      const body = init && init.body ? JSON.parse(init.body) : {};
      const plan = compilePlan(body);
      if (!plan.ok) {
        return makeResponse({
          compiled_sql: null, is_valid: 0,
          validation_message: `${plan.code}: ${plan.message}`,
          anchor_dataset: null, joined_datasets: null, execution: null,
        });
      }
      const exec = executeRows(body, plan.sql);
      return makeResponse({
        compiled_sql: plan.sql, is_valid: 1,
        validation_message: null,
        anchor_dataset: plan.anchor, joined_datasets: plan.joined.join(', ') || null,
        execution: exec,
      });
    }
    if (path === '/api/query/explain' && method === 'POST') {
      return makeResponse(explainResp());
    }

    // Import / export
    if (path === '/api/import/template' && method === 'GET') {
      return makeResponse(importTemplateResp());
    }
    if (path === '/api/import' && method === 'POST') {
      const body = init && init.body ? JSON.parse(init.body) : {};
      return makeResponse(importRunResp(body));
    }
    if ((m = path.match(/^\/api\/export\/osi\/([^/]+)$/))) {
      return makeResponse(osiExport(), 200, 'text/yaml');
    }

    return makeResponse({detail: 'demo: endpoint not mocked: ' + method + ' ' + path}, 404);
  }

  window.fetch = async function mockedFetch(resource, init) {
    try {
      const url = (typeof resource === 'string') ? resource : resource.url;
      // Only intercept same-origin calls — pass CDN requests through.
      if (/^https?:\/\//.test(url) && !url.startsWith(location.origin)) {
        return originalFetch(resource, init);
      }
      // Small latency so the UI's loading states are visible.
      await new Promise(r => setTimeout(r, 120));
      return await route(url, init);
    } catch (e) {
      console.error('[demo mock] error', e);
      return makeResponse({detail: String(e)}, 500);
    }
  };

  console.log('[demo mock] fetch interceptor installed — model:', MODEL);
})();
