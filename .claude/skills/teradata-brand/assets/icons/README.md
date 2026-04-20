# Teradata Brand-Approved Icons Library

This folder contains **753 brand-approved icons** extracted from the official Teradata Brand-Approved Icons Presentation. Each icon is available in both **PNG** and **SVG** formats (694 SVGs), organized into **58 categories**.

## Quick Start

### HTML
```html
<!-- PNG version -->
<img src="assets/icons/AI-ML/01-robot-face.png" alt="Robot" width="24" height="24" />

<!-- SVG version (recommended for web - scales better) -->
<img src="assets/icons/AI-ML/01-robot-face.svg" alt="Robot" width="24" height="24" />
```

### React/JSX
```jsx
// PNG
<img src="/assets/icons/Cloud/01-cloud-icon.png" alt="Cloud" className="w-6 h-6" />

// SVG with dynamic styling
<img src="/assets/icons/AI-ML/18-brain.svg" alt="Brain" className="w-6 h-6" style={{filter: 'brightness(0) saturate(100%)'}} />
```

### Styling SVG Icons with CSS
```css
.icon-orange { fill: #FF5F02; }
.icon-navy { fill: #00233C; }
.icon-white { fill: #FFFFFF; }
```

## Categories (58 total)

| Category | Icons | Description |
|----------|-------|-------------|
| **AI-ML** | 22 | Robots, neural networks, brains, ML concepts |
| **Analytics-Database** | 14 | Database functions, analytics operations |
| **Machine-Learning-Ops** | 11 | MLOps, pipelines, model deployment |
| **Applications** | 7 | Software apps, interfaces |
| **Cloud** | 9 | Cloud computing, services |
| **Data-Transfer** | 27 | Data movement, sync, transfer |
| **Industries-Primary** | 17 | Industry verticals |
| **Industries-Secondary** | 17 | Additional industries |
| **Organization** | 6 | Hierarchy, structure |
| **People-Users** | 15 | Users, profiles |
| **Programming** | 20 | Code, development |
| **Smart-Devices** | 25 | IoT, wearables |


## File Naming Convention

```
{number:02d}-{descriptive-name}.{png|svg}
```

Examples:
- `01-robot-face.png` + `01-robot-face.svg`
- `05-brain-clock.png` + `05-brain-clock.svg`

## Best Practices

### Sizing Guidelines
| Size | Use Case |
|------|----------|
| 16-20px | Inline text, table cells |
| 24-32px | Buttons, list items, cards |
| 48-64px | Feature highlights |
| 96px+ | Hero sections, presentations |

### Color Guidelines
- **Default**: Teradata Orange (#FF5F02) on light backgrounds
- **Dark backgrounds**: White or apply CSS filter
- **Monochrome**: Navy (#00233C) acceptable
- **Never**: Off-brand colors or gradients

### PNG vs SVG

| Format | Best For |
|--------|----------|
| PNG | Email, legacy systems, quick implementation |
| SVG | Web apps, responsive design, CSS styling |

## Source

Extracted from: **Teradata Brand-Approved Icons Presentation - Internal - SP001600.PPTX**

All icons are approved for use in Teradata-branded materials.
