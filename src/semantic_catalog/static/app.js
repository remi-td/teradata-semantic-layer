/* ------------------------------------------------------------------ *
 * Teradata Semantic Catalog — GUI logic
 * Plain ES-module-free JavaScript so it can be loaded as a single file
 * with no build step.
 * ------------------------------------------------------------------ */
'use strict';

const api = {
  async models() {
    return fetchJson('/api/models');
  },
  async tree(model) {
    return fetchJson(`/api/models/${encodeURIComponent(model)}/tree`);
  },
  async graph(model) {
    return fetchJson(`/api/models/${encodeURIComponent(model)}/graph`);
  },
  async search(q, model, kind) {
    const qs = new URLSearchParams({q});
    if (model) qs.set('model', model);
    const data = await fetchJson(`/api/search?${qs.toString()}`);
    if (kind && kind !== 'ALL') return data.filter(d => d.entity_type === kind);
    return data;
  },
  async describe(entity_type, entity_name, model) {
    const qs = new URLSearchParams({entity_type, entity_name});
    if (model) qs.set('model', model);
    return fetchJson(`/api/describe?${qs.toString()}`);
  },
  async compile(req) {
    return fetchJson('/api/query/compile', {method:'POST', body: JSON.stringify(req)});
  },
  async execute(req) {
    return fetchJson('/api/query/execute', {method:'POST', body: JSON.stringify(req)});
  },
  async explain(sql) {
    return fetchJson('/api/query/explain', {method:'POST', body: JSON.stringify({sql})});
  },
  async importTemplate() { return fetchJson('/api/import/template'); },
  async runImport(req) {
    return fetchJson('/api/import', {method:'POST', body: JSON.stringify(req)});
  },
  async exportOsi(model) {
    return fetchText(`/api/export/osi/${encodeURIComponent(model)}`);
  },
  async ping() { return fetchJson('/api/ping'); },
};

async function fetchJson(url, opts = {}) {
  opts.headers = Object.assign({'Content-Type': 'application/json'}, opts.headers || {});
  const r = await fetch(url, opts);
  if (!r.ok) {
    let detail = r.statusText;
    try { const j = await r.json(); detail = j.detail || detail; } catch (_) {}
    throw new Error(`${r.status} ${detail}`);
  }
  return r.json();
}
async function fetchText(url, opts = {}) {
  const r = await fetch(url, opts);
  if (!r.ok) {
    let detail = r.statusText;
    try { detail = await r.text(); } catch (_) {}
    throw new Error(`${r.status} ${detail}`);
  }
  return r.text();
}

// ------------------------------------------------------------------ state
const state = {
  models: [],
  currentModel: null,
  tree: null,             // parsed tree response
  graph: null,            // parsed graph response
  selection: null,        // {kind, name, model}
  filters: [],            // query builder filters
  searchKind: 'ALL',
  qb: { metrics: [], dims: [] },
};

// ------------------------------------------------------------------ util
const $ = sel => document.querySelector(sel);
const $$ = sel => Array.from(document.querySelectorAll(sel));
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const k in attrs) {
    if (k === 'class') n.className = attrs[k];
    else if (k === 'text') n.textContent = attrs[k];
    else if (k.startsWith('on')) n.addEventListener(k.slice(2).toLowerCase(), attrs[k]);
    else if (attrs[k] !== false && attrs[k] !== null && attrs[k] !== undefined) n.setAttribute(k, attrs[k]);
  }
  kids.flat().forEach(k => {
    if (k == null || k === false) return;
    n.appendChild(typeof k === 'string' ? document.createTextNode(k) : k);
  });
  return n;
};
function toast(msg, kind) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast' + (kind ? ' is-' + kind : '');
  t.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { t.hidden = true; }, 4000);
}

// ---------------------------------------------------------------- health
async function refreshHealth() {
  const badge = $('#health');
  try {
    await api.ping();
    badge.classList.remove('offline');
    badge.title = 'Database connection: OK';
  } catch (e) {
    badge.classList.add('offline');
    badge.title = 'Database unreachable: ' + e.message;
  }
}

// ---------------------------------------------------------------- model select
async function loadModels() {
  state.models = await api.models();
  const sel = $('#model-select');
  sel.innerHTML = '';
  for (const m of state.models) {
    const opt = el('option', {value: m.model_name},
      `${m.model_name}  ·  ${m.dataset_count}ds / ${m.metric_count}m / ${m.view_count}v`);
    sel.appendChild(opt);
  }
  if (!state.models.length) {
    sel.appendChild(el('option', {value:''}, 'No models found — deploy the catalog first'));
    return;
  }
  const pref = localStorage.getItem('sc.model') || state.models[0].model_name;
  const found = state.models.find(m => m.model_name === pref) || state.models[0];
  sel.value = found.model_name;
  await selectModel(found.model_name);
}

async function selectModel(name) {
  state.currentModel = name;
  $('#imp-model').value = name;
  localStorage.setItem('sc.model', name);
  state.tree = await api.tree(name);
  state.graph = await api.graph(name);
  renderTree();
  renderGraph();
  state.qb = { metrics: [], dims: [] };
  renderQueryBuilder();
  showOverview({kind:'MODEL', name});
}

// ---------------------------------------------------------------- tree
const TREE_COLLAPSE_KEY = 'sc.tree_collapsed';
function getCollapsed() {
  try { return JSON.parse(localStorage.getItem(TREE_COLLAPSE_KEY) || '{}'); } catch { return {}; }
}
function setCollapsed(k, v) {
  const c = getCollapsed(); c[k] = v; localStorage.setItem(TREE_COLLAPSE_KEY, JSON.stringify(c));
}

function renderTree() {
  const root = $('#tree'); root.innerHTML = '';
  if (!state.tree) return;
  const collapsed = getCollapsed();

  const makeGroup = (title, items, collapsibleKey, renderItem) => {
    if (!items.length) return;
    const initiallyCollapsed = collapsed[collapsibleKey] === true;
    const node = el('div', {class: 'tree-node' + (initiallyCollapsed ? ' collapsed' : '')});
    const header = el('div', {class: 'tree-header'},
      el('span', {class: 'tree-toggle'}, '▼'),
      `${title} (${items.length})`);
    header.addEventListener('click', () => {
      node.classList.toggle('collapsed');
      setCollapsed(collapsibleKey, node.classList.contains('collapsed'));
    });
    node.appendChild(header);
    const kids = el('div', {class: 'tree-children'});
    items.forEach(it => kids.appendChild(renderItem(it)));
    node.appendChild(kids);
    root.appendChild(node);
  };

  const datasetItem = (d) => {
    const cls = d.sub_kind === 'CUBE' ? 'icon-ds-cube' : 'icon-ds-table';
    const row = el('div', {class: 'tree-item', 'data-kind': 'DATASET', 'data-name': d.name},
      el('span', {class:'tree-icon ' + cls, title: d.sub_kind}, d.sub_kind === 'CUBE' ? 'C' : 'T'),
      d.name);
    row.addEventListener('click', (e) => { e.stopPropagation(); selectEntity({kind:'DATASET', name: d.name}); });
    return row;
  };

  const metricItem = (m) => {
    const row = el('div', {class: 'tree-item', 'data-kind':'METRIC', 'data-name': m.name},
      el('span', {class:'tree-icon icon-metric', title:m.type}, 'Σ'),
      m.name);
    if (m.is_certified) row.title = 'certified';
    row.addEventListener('click', () => selectEntity({kind:'METRIC', name: m.name}));
    return row;
  };

  const viewItem = (v) => {
    const row = el('div', {class: 'tree-item', 'data-kind':'VIEW', 'data-name': v.name},
      el('span', {class:'tree-icon icon-view'}, 'V'),
      v.name);
    row.addEventListener('click', () => selectEntity({kind:'VIEW', name: v.name}));
    return row;
  };

  makeGroup('Datasets', state.tree.datasets || [], 'datasets', datasetItem);
  makeGroup('Metrics',  state.tree.metrics  || [], 'metrics',  metricItem);
  makeGroup('Views',    state.tree.views    || [], 'views',    viewItem);
  // Relationships — clickable, opens detail in right drawer.
  if ((state.tree.relationships || []).length) {
    const initiallyCollapsed = collapsed['relationships'] !== false; // default collapsed
    const node = el('div', {class: 'tree-node' + (initiallyCollapsed ? ' collapsed' : '')});
    const header = el('div', {class: 'tree-header'},
      el('span', {class:'tree-toggle'}, '▼'),
      `Relationships (${state.tree.relationships.length})`);
    header.addEventListener('click', () => {
      node.classList.toggle('collapsed');
      setCollapsed('relationships', node.classList.contains('collapsed'));
    });
    node.appendChild(header);
    const kids = el('div', {class: 'tree-children'});
    state.tree.relationships.forEach(r => {
      const keyName = r.name || `${r.from}__${r.to}`;
      const row = el('div', {class:'tree-item', 'data-kind':'RELATIONSHIP', 'data-name': keyName},
        el('span', {class:'tree-icon icon-field'}, '↔'),
        `${r.from} → ${r.to}`);
      row.title = `${r.name || ''} (${r.cardinality || '—'})`;
      row.addEventListener('click', () => selectEntity({kind:'RELATIONSHIP', name: keyName}));
      kids.appendChild(row);
    });
    node.appendChild(kids);
    $('#tree').appendChild(node);
  }
  highlightSelectionInTree();
}

function highlightSelectionInTree() {
  $$('.tree-item').forEach(n => n.classList.remove('active'));
  if (!state.selection) return;
  const kind = state.selection.kind;
  const name = state.selection.name;
  const n = document.querySelector(
    `.tree-item[data-kind="${kind}"][data-name="${CSS.escape(name)}"]`);
  if (n) n.classList.add('active');
}

// ---------------------------------------------------------------- graph
let cy = null;

function renderGraph() {
  if (cy) { cy.destroy(); cy = null; }
  if (!state.graph) return;

  const nodes = state.graph.nodes.map(n => ({
    data: {
      id: n.id, label: n.label, kind: n.kind, sub_kind: n.sub_kind || '',
      description: n.description || '',
    }
  }));
  const edges = state.graph.edges.map(e => ({
    data: {
      id: e.id, source: e.source, target: e.target, kind: e.kind,
      // Prefer role_name as the edge label — it's the disambiguator a user
      // needs to see when two edges connect the same pair. Fall back to the
      // relationship_name when no role is declared.
      label: e.role_name || e.label || '',
      cardinality: e.cardinality || '',
      role_name: e.role_name || '',
      relationship_name: e.label || '',
    }
  }));

  cy = cytoscape({
    container: document.getElementById('cy'),
    elements: [...nodes, ...edges],
    wheelSensitivity: 0.2,
    style: [
      // DATASET (table)
      { selector: 'node[kind = "DATASET"][sub_kind = "TABLE"]', style: {
        'shape': 'round-rectangle',
        'background-color': '#0A4467',
        'border-color': '#00233C', 'border-width': 2,
        'color': '#FFFFFF',
        'label': 'data(label)',
        'font-family': 'Inter, sans-serif', 'font-size': 13, 'font-weight': 600,
        'text-valign': 'center', 'text-halign': 'center',
        'padding': '12px', 'width': 'label', 'height': 38,
        'text-margin-y': 0,
      }},
      // DATASET (cube)
      { selector: 'node[kind = "DATASET"][sub_kind = "CUBE"]', style: {
        'shape': 'round-rectangle',
        'background-color': '#C04A00',
        'border-color': '#8E3600', 'border-width': 2,
        'color': '#FFFFFF',
        'label': 'data(label)',
        'font-family': 'Inter, sans-serif', 'font-size': 13, 'font-weight': 600,
        'text-valign': 'center', 'text-halign': 'center',
        'padding': '12px', 'width': 'label', 'height': 38,
      }},
      // METRIC
      { selector: 'node[kind = "METRIC"]', style: {
        'shape': 'ellipse',
        'background-color': '#FF5F02',
        'border-color': '#C04A00', 'border-width': 2,
        'color': '#00233C',
        'label': 'data(label)',
        'font-family': 'Inter, sans-serif', 'font-size': 11, 'font-weight': 500,
        'text-valign': 'bottom', 'text-halign': 'center', 'text-margin-y': 4,
        'width': 24, 'height': 24,
      }},
      // VIEW
      { selector: 'node[kind = "VIEW"]', style: {
        'shape': 'round-rectangle',
        'background-color': '#D8BFD8',
        'border-color': '#8D70A0', 'border-width': 2, 'border-style': 'dashed',
        'color': '#00233C',
        'label': 'data(label)',
        'font-family': 'Inter, sans-serif', 'font-size': 12, 'font-weight': 500,
        'text-valign': 'center', 'text-halign': 'center',
        'padding': '10px', 'width': 'label', 'height': 30,
      }},
      // selection
      { selector: 'node:selected', style: {
        'border-color': '#FF5F02', 'border-width': 4,
      }},
      // edges
      { selector: 'edge[kind = "RELATIONSHIP"]', style: {
        'width': 1.5,
        'line-color': '#4A90E2',
        'target-arrow-color': '#4A90E2',
        'target-arrow-shape': 'triangle',
        'curve-style': 'bezier',
        'label': 'data(label)',
        'font-size': 10, 'color': '#4A90E2', 'font-weight': 500,
        'text-background-color': '#FFFFFF',
        'text-background-opacity': 0.8,
        'text-background-padding': 2,
      }},
      { selector: 'edge[kind = "METRIC_OF"]', style: {
        'width': 1,
        'line-color': '#FF5F02',
        'line-style': 'dashed',
        'curve-style': 'bezier',
        'target-arrow-shape': 'none',
      }},
      { selector: 'edge[kind = "VIEW_OF"]', style: {
        'width': 1,
        'line-color': '#8D70A0',
        'line-style': 'dotted',
        'curve-style': 'bezier',
        'target-arrow-shape': 'none',
      }},
      { selector: 'edge:selected', style: {
        'line-color': '#FF5F02',
        'target-arrow-color': '#FF5F02',
        'width': 3,
      }},
    ],
    layout: fcoseLayout({randomize: true}),
  });

  // If the container wasn't sized yet when we created the graph (common on
  // the very first load), resize + re-run the layout once it has real
  // dimensions. Otherwise nodes pile up on the top-left corner.
  requestAnimationFrame(() => {
    if (!cy) return;
    cy.resize();
    cy.layout(fcoseLayout({randomize: true})).run();
  });

  cy.on('tap', 'node', evt => {
    const d = evt.target.data();
    if (d.kind === 'DATASET') selectEntity({kind: 'DATASET', name: d.label});
    else if (d.kind === 'METRIC') selectEntity({kind: 'METRIC', name: d.label});
    else if (d.kind === 'VIEW') selectEntity({kind: 'VIEW', name: d.label});
  });

  cy.on('tap', evt => {
    if (evt.target === cy) highlightGraphSelection();
  });
}

function fcoseLayout({randomize = false} = {}) {
  return {
    name: 'fcose',
    animate: true, animationDuration: 500,
    nodeRepulsion: 10000,
    idealEdgeLength: 130,
    edgeElasticity: 0.3,
    nestingFactor: 0.8,
    gravity: 0.25,
    numIter: 2500,
    padding: 40,
    // Initial layouts need random seeding: Cytoscape starts every node at
    // (0,0), so a non-randomised run collapses to a diagonal. Re-layouts
    // of an already-placed graph keep positions stable.
    randomize,
  };
}

function highlightGraphSelection() {
  if (!cy) return;
  cy.$('node, edge').removeClass('hl-focus');
  if (!state.selection) return;
  let id = null;
  if (state.selection.kind === 'DATASET') {
    const match = state.graph.nodes.find(n => n.kind === 'DATASET' && n.label === state.selection.name);
    if (match) id = match.id;
  } else if (state.selection.kind === 'METRIC') {
    const match = state.graph.nodes.find(n => n.kind === 'METRIC' && n.label === state.selection.name);
    if (match) id = match.id;
  } else if (state.selection.kind === 'VIEW') {
    const match = state.graph.nodes.find(n => n.kind === 'VIEW' && n.label === state.selection.name);
    if (match) id = match.id;
  }
  if (id) {
    const node = cy.getElementById(id);
    if (node.nonempty()) {
      cy.$('node:selected, edge:selected').unselect();
      node.select();
      cy.animate({center: {eles: node}, zoom: Math.max(0.9, cy.zoom())}, {duration: 350});
    }
  }
}

// ----------------------------------------------------------------- tabs
$$('.tab').forEach(btn => {
  btn.addEventListener('click', () => {
    $$('.tab').forEach(b => b.classList.remove('tab-active'));
    btn.classList.add('tab-active');
    const tab = btn.dataset.tab;
    $$('.panel').forEach(p => p.classList.toggle('panel-active', p.dataset.panel === tab));
    if (tab === 'graph' && cy) setTimeout(() => cy.resize(), 50);
  });
});

// --------------------------------------------------------- drawer (right)
$$('.dtab').forEach(btn => {
  btn.addEventListener('click', () => {
    $$('.dtab').forEach(b => b.classList.remove('dtab-active'));
    btn.classList.add('dtab-active');
    const t = btn.dataset.dtab;
    $$('.dpane').forEach(p => p.classList.remove('dpane-active'));
    $('#dp-' + t).classList.add('dpane-active');
  });
});

function showOverview(sel) {
  state.selection = sel;
  highlightSelectionInTree();
  highlightGraphSelection();
  $('#drawer-kind').textContent = sel.kind;
  $('#drawer-name').textContent = sel.name || '—';
  $('#drawer-sub').textContent = '';
  const pane = $('#dp-overview'); pane.innerHTML = '';
  $('#dp-fields').innerHTML = ''; $('#dp-metrics').innerHTML = '';
  $('#dp-sql').innerHTML = ''; $('#dp-ai').innerHTML = '';
  $('#dtab-fields').hidden = true;
  $('#dtab-metrics').hidden = true;
  $('#dtab-sql').hidden = true;

  if (sel.kind === 'MODEL') {
    const m = state.models.find(x => x.model_name === state.currentModel);
    if (!m) return;
    pane.appendChild(el('p', {}, m.description || 'No description.'));
    pane.appendChild(el('ul', {class:'kv-list'},
      kv('Model',   m.model_name),
      kv('Datasets', String(m.dataset_count)),
      kv('Metrics',  String(m.metric_count)),
      kv('Views',    String(m.view_count)),
    ));
    return;
  }

  if (sel.kind === 'DATASET') {
    const ds = (state.tree.datasets || []).find(d => d.name === sel.name);
    if (!ds) return;
    $('#drawer-sub').textContent = ds.description || '';
    pane.appendChild(el('ul', {class:'kv-list'},
      kv('Kind', ds.sub_kind + (ds.sub_kind === 'CUBE' ? ' (flattened)' : ' (table/view)')),
      kv('Fields', String((ds.fields || []).length)),
      kv('ID', String(ds.id)),
    ));
    $('#dp-fields').innerHTML = '';
    $('#dp-fields').appendChild(renderFields(ds.fields || []));
    $('#dtab-fields').hidden = false;
    // metrics on this dataset
    const metrics = (state.tree.metrics || []).filter(m => m.primary_dataset === sel.name);
    if (metrics.length) {
      $('#dp-metrics').innerHTML = '';
      metrics.forEach(m => $('#dp-metrics').appendChild(renderMetricCard(m)));
      $('#dtab-metrics').hidden = false;
    }
    // expose describe async for ai context + source_query
    loadDescribeInto(sel);
    return;
  }

  if (sel.kind === 'METRIC') {
    const m = (state.tree.metrics || []).find(x => x.name === sel.name);
    if (m) {
      $('#drawer-sub').textContent = m.description || '';
      pane.appendChild(el('ul', {class:'kv-list'},
        kv('Type', m.type),
        kv('Primary dataset', m.primary_dataset || '—'),
        kv('Certified', m.is_certified ? 'yes' : 'no'),
      ));
    }
    loadDescribeInto(sel);
    return;
  }

  if (sel.kind === 'VIEW') {
    const v = (state.tree.views || []).find(x => x.name === sel.name);
    if (v) {
      $('#drawer-sub').textContent = v.description || '';
      pane.appendChild(el('ul', {class:'kv-list'},
        kv('Primary dataset', v.primary_dataset || '—'),
        kv('Certified',       v.is_certified ? 'yes' : 'no'),
      ));
    }
    loadDescribeInto(sel);
    return;
  }

  if (sel.kind === 'FIELD') {
    loadDescribeInto(sel);
    return;
  }

  if (sel.kind === 'RELATIONSHIP') {
    const rel = (state.tree.relationships || []).find(
      r => (r.name || `${r.from}__${r.to}`) === sel.name
    );
    if (!rel) return;
    $('#drawer-kind').textContent = 'RELATIONSHIP';
    $('#drawer-name').textContent = rel.name || `${rel.from} → ${rel.to}`;
    $('#drawer-sub').textContent = `${rel.from} → ${rel.to}`;
    const cols = (rel.from_columns || []).map((c, i) =>
      `${rel.from}.${c} = ${rel.to}.${(rel.to_columns || [])[i] || '?'}`
    ).join('\n');
    pane.appendChild(el('ul', {class:'kv-list'},
      kv('From',        rel.from),
      kv('To',          rel.to),
      kv('Cardinality', rel.cardinality || '—'),
      kv('Join type',   rel.join_type_hint || '—'),
      kv('Role',        rel.role_name || '—'),
    ));
    if (cols) {
      pane.appendChild(el('h4', {}, 'Join columns'));
      pane.appendChild(el('pre', {class:'sql'}, cols));
    }
    return;
  }
}

function kv(k, v) {
  return el('li', {}, el('span', {class:'k'}, k), el('span', {class:'v'}, v || '—'));
}

function renderFields(fields) {
  const ul = el('ul', {class:'field-list'});
  for (const f of fields) {
    let iconCls = 'icon-field';
    let icon = 'a';
    if (f.type === 'K') { iconCls = 'icon-key'; icon = 'K'; }
    else if (f.is_time_dimension) { iconCls = 'icon-time'; icon = '⏲'; }
    else if (f.is_dimension)     { iconCls = 'icon-field'; icon = 'd'; }
    const li = el('li', {},
      el('span', {class: 'tree-icon ' + iconCls, title: f.type}, icon),
      el('span', {}, f.name),
      el('span', {class:'f-type'}, f.data_type || ''));
    li.addEventListener('click', () => {
      selectEntity({kind:'FIELD', name: f.name, parent: undefined});
    });
    ul.appendChild(li);
  }
  return ul;
}

function renderMetricCard(m) {
  return el('div', {class:'metric-card'},
    el('div', {class:'m-name'}, m.name + (m.is_certified ? ' ✓' : '')),
    m.description ? el('div', {class:'m-desc'}, m.description) : '',
    el('div', {class:'m-expr'}, `type: ${m.type}${m.primary_dataset ? ' · ds: ' + m.primary_dataset : ''}`),
  );
}

async function loadDescribeInto(sel) {
  try {
    const d = await api.describe(sel.kind, sel.name, state.currentModel);
    const ov = $('#dp-overview');
    const ul = el('ul', {class:'kv-list'});
    // Keys that render elsewhere (SQL tab, AI tab) or are redundant.
    // expression_ANSI_SQL is dropped: the catalog keeps it for OSI export
    // but the UI always shows the Teradata dialect as "expression".
    const ignoreForOverview = new Set([
      'ai_synonyms', 'ai_instructions', 'ai_examples', 'display_name',
      'source_query', 'physical_source',
      'expression_TERADATA', 'expression_ANSI_SQL',
    ]);
    for (const a of d.attributes) {
      if (ignoreForOverview.has(a.attr_key)) continue;
      if (!a.attr_value) continue;
      ul.appendChild(kv(a.attr_key, a.attr_value));
    }
    // keep existing content (summary) and append the full key/value table
    ov.appendChild(ul);

    // SQL tab for datasets and metrics. Show only the Teradata dialect;
    // label it plainly "expression" since dialect choice is an implementation
    // detail, not something the user needs to pick.
    const sqlAttrs = d.attributes.filter(a =>
      a.attr_key === 'source_query'
      || a.attr_key === 'physical_source'
      || a.attr_key === 'expression_TERADATA');
    if (sqlAttrs.length) {
      const p = $('#dp-sql'); p.innerHTML = '';
      for (const a of sqlAttrs) {
        const label = a.attr_key === 'expression_TERADATA' ? 'expression' : a.attr_key;
        p.appendChild(el('h3', {}, label));
        p.appendChild(el('pre', {class:'sql'}, a.attr_value));
      }
      $('#dtab-sql').hidden = false;
    }

    // AI context tab
    const aiAttrs = d.attributes.filter(a =>
      a.attr_key === 'ai_instructions' || a.attr_key === 'ai_synonyms'
      || a.attr_key === 'ai_examples' || a.attr_key === 'display_name');
    const ai = $('#dp-ai'); ai.innerHTML = '';
    if (aiAttrs.length) {
      const ulAi = el('ul', {class:'kv-list'});
      for (const a of aiAttrs) {
        ulAi.appendChild(kv(a.attr_key, a.attr_value));
      }
      ai.appendChild(ulAi);
    } else {
      ai.appendChild(el('p', {class:'hint'}, 'No AI context set for this entity.'));
    }
  } catch (e) {
    toast('Describe failed: ' + e.message, 'error');
  }
}

function selectEntity(sel) { showOverview(sel); }

// ---------------------------------------------------------------- search
let searchDeb = 0;
$('#search-input').addEventListener('input', (ev) => {
  clearTimeout(searchDeb);
  searchDeb = setTimeout(() => runSearch(ev.target.value.trim()), 180);
});
$$('#search-filter-chips .chip').forEach(c => {
  c.addEventListener('click', () => {
    $$('#search-filter-chips .chip').forEach(x => x.classList.remove('chip-active'));
    c.classList.add('chip-active');
    state.searchKind = c.dataset.kind;
    runSearch($('#search-input').value.trim());
  });
});

async function runSearch(q) {
  const panel = $('#search-results');
  if (!q) { panel.hidden = true; panel.innerHTML = ''; return; }
  try {
    const hits = await api.search(q, state.currentModel, state.searchKind);
    panel.innerHTML = '';
    if (!hits.length) {
      panel.appendChild(el('div', {class:'sr-item'}, 'No matches'));
    } else {
      for (const h of hits.slice(0, 40)) {
        const item = el('div', {class:'sr-item'},
          el('span', {class:'sr-kind sr-' + h.entity_type}, h.entity_type),
          h.entity_name,
          h.parent_name ? el('span', {class:'sr-parent'}, h.parent_name) : '',
        );
        item.addEventListener('click', () => {
          selectEntity({kind: h.entity_type, name: h.entity_name});
          panel.hidden = true;
          $('#search-input').value = '';
        });
        panel.appendChild(item);
      }
    }
    panel.hidden = false;
  } catch (e) {
    toast('Search failed: ' + e.message, 'error');
  }
}

// ---------------------------------------------------------------- graph toolbar
$('#btn-graph-fit').addEventListener('click', () => { if (cy) cy.fit(null, 40); });
$('#btn-graph-relayout').addEventListener('click', () => { if (cy) cy.layout(fcoseLayout()).run(); });
$('#btn-refresh').addEventListener('click', () => selectModel(state.currentModel));
$('#btn-export-osi').addEventListener('click', async () => {
  $$('.tab').forEach(b => b.classList.remove('tab-active'));
  document.querySelector('.tab[data-tab="export"]').classList.add('tab-active');
  $$('.panel').forEach(p => p.classList.toggle('panel-active', p.dataset.panel === 'export'));
  await exportOsi();
});

$('#model-select').addEventListener('change', e => selectModel(e.target.value));

// ------------------------------------------------------------ query builder
const OP_LIST = ['=','<>','<','<=','>','>=','LIKE','IN'];

function renderQueryBuilder() {
  renderQbChips();
  renderFilterRows();
}

function renderQbChips() {
  const metricsEl = $('#qb-metrics'); metricsEl.innerHTML = '';
  state.qb.metrics.forEach(m => {
    const c = el('button', {class:'chip-select is-metric'}, m,
      el('span', {class:'chip-x'}, '×'));
    c.addEventListener('click', () => {
      state.qb.metrics = state.qb.metrics.filter(x => x !== m);
      renderQbChips();
    });
    metricsEl.appendChild(c);
  });
  const addM = el('button', {class:'chip-select add'}, '+ metric');
  addM.addEventListener('click', (e) => openPicker(e.currentTarget, 'METRIC', (name) => {
    if (!state.qb.metrics.includes(name)) state.qb.metrics.push(name);
    renderQbChips();
  }));
  metricsEl.appendChild(addM);

  const dimsEl = $('#qb-dims'); dimsEl.innerHTML = '';
  state.qb.dims.forEach(d => {
    const c = el('button', {class:'chip-select'}, d,
      el('span', {class:'chip-x'}, '×'));
    c.addEventListener('click', () => {
      state.qb.dims = state.qb.dims.filter(x => x !== d);
      renderQbChips();
    });
    dimsEl.appendChild(c);
  });
  const addD = el('button', {class:'chip-select add'}, '+ dimension');
  addD.addEventListener('click', (e) => openPicker(e.currentTarget, 'DIM', (name) => {
    if (!state.qb.dims.includes(name)) state.qb.dims.push(name);
    renderQbChips();
  }));
  dimsEl.appendChild(addD);
}

function openPicker(anchor, kind, onPick) {
  const items = [];
  if (kind === 'METRIC') {
    (state.tree.metrics || []).forEach(m => items.push({
      key: m.name, label: m.name, sub: m.type + (m.primary_dataset ? ' · ' + m.primary_dataset : ''),
    }));
  } else {
    // Role-play awareness. For each dataset, count incoming relationships.
    // If >1, the dataset is role-played and the plain `dataset.field` token
    // is ambiguous — surface one entry per role_name instead.
    const inBy = {};   // ds_name -> [{...rel}]
    const outBy = {};  // ds_name -> [{...rel}]
    (state.tree.relationships || []).forEach(r => {
      (inBy[r.to]   = inBy[r.to]   || []).push(r);
      (outBy[r.from] = outBy[r.from] || []).push(r);
    });

    const dsMap = {};
    (state.tree.datasets || []).forEach(ds => { dsMap[ds.name] = ds; });

    // Collect fields reachable from a role prefix via BFS over outgoing rels.
    // Returns [{key, label, sub}] — fields on the direct target AND on any
    // transitively reachable dataset (e.g. customer_nation.r_name via nation→region).
    function fieldsForRole(prefix, startDsName, viaFromName) {
      const result = [];
      const visited = new Set();
      const queue = [[startDsName, false]]; // [dsName, isTransitive]
      while (queue.length) {
        const [curName, isTransitive] = queue.shift();
        if (visited.has(curName)) continue;
        visited.add(curName);
        const curDs = dsMap[curName];
        if (!curDs) continue;
        (curDs.fields || []).forEach(f => {
          if (!f.is_dimension && f.type !== 'K' && !f.is_time_dimension) return;
          const grainSuffix = f.is_time_dimension ? ':MONTH' : '';
          const typeTag = f.is_time_dimension ? 'time' : (f.type === 'K' ? 'key' : 'dimension');
          const transitiveNote = isTransitive ? ` · via ${curName}` : '';
          result.push({
            key: `${prefix}.${f.name}${grainSuffix}`,
            label: `${prefix}.${f.name}`,
            sub: `${typeTag} · via ${viaFromName}${transitiveNote}`,
          });
        });
        // Walk outgoing edges to gather transitive fields
        (outBy[curName] || []).forEach(r => {
          if (!visited.has(r.to)) queue.push([r.to, true]);
        });
      }
      return result;
    }

    (state.tree.datasets || []).forEach(ds => {
      const incoming = inBy[ds.name] || [];
      const rolePlayed = incoming.length > 1;
      if (!rolePlayed) {
        // Unambiguous dataset: surface its own fields with plain dataset.field tokens.
        // Do NOT surface transitive fields here — they'll be captured under their
        // own dataset entries (or under role prefixes if role-played).
        (ds.fields || []).forEach(f => {
          if (!f.is_dimension && f.type !== 'K' && !f.is_time_dimension) return;
          const grainSuffix = f.is_time_dimension ? ':MONTH' : '';
          const typeTag = f.is_time_dimension ? 'time' : (f.type === 'K' ? 'key' : 'dimension');
          items.push({
            key: `${ds.name}.${f.name}${grainSuffix}`,
            label: `${ds.name}.${f.name}`,
            sub: typeTag,
          });
        });
        return;
      }
      // Role-played: one entry per role, including fields from transitively
      // reachable datasets (e.g. customer_nation.r_name via nation→region).
      incoming.forEach(r => {
        const prefix = r.role_name || r.name;
        fieldsForRole(prefix, ds.name, r.from).forEach(item => items.push(item));
      });
    });
  }
  showMenu(anchor, items, onPick);
}

function showMenu(anchor, items, onPick) {
  document.querySelectorAll('.menu').forEach(m => m.remove());
  const menu = el('div', {class:'menu'});
  const input = el('input', {placeholder:'Filter…', autofocus:true});
  menu.appendChild(input);
  const listHost = el('div', {});
  menu.appendChild(listHost);
  const render = (q) => {
    listHost.innerHTML = '';
    const ql = q.toLowerCase();
    items.filter(it => !q || it.label.toLowerCase().includes(ql)).slice(0, 80).forEach(it => {
      const row = el('div', {class:'menu-item'},
        el('span', {}, it.label),
        it.sub ? el('span', {class:'sr-parent'}, it.sub) : '');
      row.addEventListener('click', () => { onPick(it.key); menu.remove(); });
      listHost.appendChild(row);
    });
  };
  render('');
  input.addEventListener('input', () => render(input.value));

  const rect = anchor.getBoundingClientRect();
  menu.style.top = (rect.bottom + 4) + 'px';
  menu.style.left = rect.left + 'px';
  document.body.appendChild(menu);
  setTimeout(() => input.focus(), 10);

  const off = (ev) => {
    if (!menu.contains(ev.target)) { menu.remove(); document.removeEventListener('mousedown', off); }
  };
  document.addEventListener('mousedown', off);
}

function renderFilterRows() {
  const host = $('#qb-filters'); host.innerHTML = '';
  state.filters.forEach((f, i) => host.appendChild(renderFilterRow(f, i)));
}

function renderFilterRow(f, i) {
  const fieldInput = el('input', {value: f.field || '', placeholder: 'dataset.field or metric'});
  fieldInput.addEventListener('input', () => f.field = fieldInput.value);
  const opSel = el('select', {},
    ...OP_LIST.map(o => el('option', {value: o, selected: o === f.op}, o)));
  opSel.addEventListener('change', () => f.op = opSel.value);
  const valInput = el('input', {value: f.value || '', placeholder: f.op === 'IN' ? "('A','B')" : 'value'});
  valInput.addEventListener('input', () => f.value = valInput.value);
  const kill = el('button', {class:'btn-x', title:'Remove'}, '✕');
  kill.addEventListener('click', () => { state.filters.splice(i, 1); renderFilterRows(); });
  return el('div', {class:'filter-row'}, fieldInput, opSel, valInput, kill);
}
$('#btn-add-filter').addEventListener('click', () => {
  state.filters.push({field:'', op:'=', value:''});
  renderFilterRows();
});

function buildQueryRequest() {
  const where  = [];
  const having = [];
  const metricsSet = new Set(state.qb.metrics);
  for (const f of state.filters) {
    if (!f.field) continue;
    if (metricsSet.has(f.field)) {
      having.push({metric: f.field, op: f.op, value: f.value, type: guessType(f.value)});
    } else {
      if (f.op.toUpperCase() === 'IN') {
        // Accept raw tuple "('A','B')" or comma-separated "A,B"
        const raw = (f.value || '').trim();
        if (raw.startsWith('(') && raw.endsWith(')')) {
          // Leave as-is: send value with type RAW so the server passes it verbatim.
          where.push({field: f.field, op: 'IN', values: [], type: 'RAW', value: raw});
        } else {
          where.push({field: f.field, op: 'IN', values: raw.split(',').map(s => s.trim()).filter(Boolean)});
        }
      } else {
        where.push({field: f.field, op: f.op, value: f.value, type: guessType(f.value)});
      }
    }
  }
  const sortStr = ($('#qb-sort').value || '').trim();
  const sort = [];
  if (sortStr) {
    sortStr.split(',').forEach(tok => {
      const parts = tok.trim().split(/\s+/);
      if (parts[0]) sort.push({field: parts[0], direction: (parts[1] || 'ASC').toUpperCase()});
    });
  }
  return {
    model: state.currentModel,
    metrics: state.qb.metrics.slice(),
    dimensions: state.qb.dims.slice(),
    where, having, sort,
    limit: parseInt($('#qb-limit').value || '0', 10) || 0,
    execute: false,
  };
}

function guessType(v) {
  if (v == null || v === '') return undefined;
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(v))) return 'DATE';
  if (/^-?\d+(\.\d+)?$/.test(String(v))) return 'NUMBER';
  return undefined;
}

async function runCompile(execute) {
  const req = buildQueryRequest();
  if (!req.metrics.length && !req.dimensions.length) {
    toast('Pick at least one metric or dimension', 'error');
    return;
  }
  setQbStatus('Compiling…');
  try {
    const r = execute ? await api.execute(req) : await api.compile(req);
    $('#qb-sql').textContent = r.compiled_sql || '(no SQL produced)';
    $('#qb-anchor').textContent = (r.anchor_dataset ? 'anchor: ' + r.anchor_dataset : '')
      + (r.joined_datasets ? ' · joins: ' + r.joined_datasets : '');
    if (r.is_valid === 1) {
      setQbStatus(r.validation_message || 'Compiled successfully', 'ok');
    } else {
      setQbStatus(r.validation_message || 'Compile failed', 'error');
    }
    renderResults(r.execution);
  } catch (e) {
    setQbStatus('Compile failed: ' + e.message, 'error');
  }
}
function setQbStatus(msg, kind) {
  const el = $('#qb-status');
  el.textContent = msg;
  el.classList.remove('is-ok', 'is-error');
  if (kind === 'ok') el.classList.add('is-ok');
  if (kind === 'error') el.classList.add('is-error');
}

function renderResults(execution) {
  const host = $('#qb-results'); host.innerHTML = '';
  $('#qb-row-count').textContent = '';
  if (!execution) return;
  const {columns, rows, row_count, truncated} = execution;
  $('#qb-row-count').textContent = `${row_count} row${row_count === 1 ? '' : 's'}` +
    (truncated ? ' (showing first 500)' : '');
  const table = el('table', {},
    el('thead', {}, el('tr', {}, ...columns.map(c => el('th', {}, c)))),
    el('tbody', {}, ...rows.map(r =>
      el('tr', {}, ...columns.map((_, i) => el('td', {}, formatCell(r[i]))))
    )),
  );
  host.appendChild(table);
}
function formatCell(v) {
  if (v == null) return '';
  if (typeof v === 'number') {
    if (Number.isInteger(v)) return v.toString();
    return v.toLocaleString(undefined, {maximumFractionDigits: 4});
  }
  return String(v);
}
$('#btn-compile').addEventListener('click', () => runCompile(false));
$('#btn-execute').addEventListener('click', () => runCompile(true));
$('#btn-qb-reset').addEventListener('click', () => {
  state.qb = {metrics:[], dims:[]}; state.filters = [];
  $('#qb-limit').value = 100; $('#qb-sort').value = '';
  renderQueryBuilder(); $('#qb-sql').textContent = ''; $('#qb-status').textContent = '';
  $('#qb-results').innerHTML = ''; $('#qb-row-count').textContent = '';
});
$('#btn-explain').addEventListener('click', async () => {
  const sql = $('#qb-sql').textContent.trim();
  if (!sql) { toast('Compile a query first', 'error'); return; }
  $('#qb-explain-card').hidden = false;
  $('#qb-explain').textContent = 'running EXPLAIN…';
  try {
    const r = await api.explain(sql);
    $('#qb-explain').textContent = r.ok ? r.plan : 'EXPLAIN failed: ' + (r.message || '');
  } catch (e) {
    $('#qb-explain').textContent = 'EXPLAIN error: ' + e.message;
  }
});
$('#btn-close-explain').addEventListener('click', () => { $('#qb-explain-card').hidden = true; });
$('#btn-copy-sql').addEventListener('click', () => {
  const t = $('#qb-sql').textContent || '';
  navigator.clipboard.writeText(t).then(() => toast('Copied'), () => toast('Copy failed', 'error'));
});

// ---------------------------------------------------------------- import
const IMPORT_EXAMPLE = `# Add a new metric to an existing model
model: tpch_orders
metrics:
  - name: my_total_qty
    description: Total units sold across line items
    primary_dataset: lineitem
    metric_type: SIMPLE
    is_additive: 1
    expressions:
      TERADATA: "SUM(lineitem.l_quantity)"
      ANSI_SQL: "SUM(l_quantity)"
ai_context:
  - entity_type: METRIC
    entity_name: my_total_qty
    instructions: Total units sold. Additive across every dimension.
    synonyms: [units, volume, quantity sold]
    display_name: Total units
`;

$('#btn-imp-template').addEventListener('click', () => {
  $('#imp-text').value = IMPORT_EXAMPLE;
});
$('#btn-imp-validate').addEventListener('click', () => runImport(true));
$('#btn-imp-apply').addEventListener('click', () => runImport(false));

async function runImport(dryRun) {
  const model = $('#imp-model').value.trim() || state.currentModel;
  const text  = $('#imp-text').value;
  if (!text.trim()) { toast('Paste something to import', 'error'); return; }
  $('#imp-results').innerHTML = '<p class="hint">Running…</p>';
  $('#imp-summary').textContent = '';
  try {
    const r = await api.runImport({model, text, dry_run: !!dryRun});
    renderImportResults(r);
    const verb = r.dry_run ? (r.error_count ? 'Validation found errors' : 'Validation passed')
                           : (r.applied ? 'Applied successfully' : 'Apply failed');
    toast(verb, r.error_count ? 'error' : 'ok');
    if (!r.dry_run && r.applied) {
      // reload tree/graph so new entities appear
      selectModel(state.currentModel);
    }
  } catch (e) {
    $('#imp-results').innerHTML = '';
    $('#imp-results').appendChild(el('div', {class:'imp-row error'},
      el('span', {class:'imp-ord'}, '!'),
      el('span', {class:'imp-name'}, 'Request failed'),
      el('span', {class:'imp-msg'}, e.message),
    ));
  }
}

function renderImportResults(r) {
  const host = $('#imp-results'); host.innerHTML = '';
  $('#imp-summary').textContent =
    `${r.total} items · ${r.ok_count} ok · ${r.error_count} errors · ${r.dry_run ? 'dry run' : (r.applied ? 'applied' : 'rolled back')}`;
  for (const row of r.results) {
    const klass = row.status === 'OK' ? 'ok' : 'error';
    host.appendChild(el('div', {class: 'imp-row ' + klass},
      el('span', {class:'imp-ord'}, String(row.ord)),
      el('span', {class:'imp-name'}, `${row.kind} · ${row.name || ''}`),
      el('span', {class:'imp-msg'},  row.message || ''),
    ));
  }
}

// ---------------------------------------------------------------- export
async function exportOsi() {
  $('#exp-text').textContent = 'Generating…';
  try {
    const txt = await api.exportOsi(state.currentModel);
    $('#exp-text').textContent = txt;
    $('#exp-text').dataset.filename = state.currentModel + '.osi.yaml';
  } catch (e) {
    $('#exp-text').textContent = 'Failed: ' + e.message;
  }
}
$('#btn-exp-osi').addEventListener('click', exportOsi);
$('#btn-exp-copy').addEventListener('click', () => {
  const t = $('#exp-text').textContent || '';
  if (!t) return;
  navigator.clipboard.writeText(t).then(() => toast('Copied'), () => toast('Copy failed','error'));
});
$('#btn-exp-download').addEventListener('click', () => {
  const t = $('#exp-text').textContent || '';
  if (!t) return;
  const name = $('#exp-text').dataset.filename || 'export.yaml';
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([t], {type: 'text/yaml'}));
  a.download = name; a.click(); URL.revokeObjectURL(a.href);
});

// ---------------------------------------------------------------- boot
(async function boot() {
  try {
    await refreshHealth();
    await loadModels();
  } catch (e) {
    toast('Could not reach the server: ' + e.message, 'error');
  }
  setInterval(refreshHealth, 30000);
})();
