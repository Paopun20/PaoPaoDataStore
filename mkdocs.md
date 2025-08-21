site_name: PPDB Documentation
nav:
  - Home: index.md
  - API Reference: api.md
theme:
  name: material
  palette:
    primary: 'deep orange'
    accent: 'deep orange'
  font:
    text: 'Roboto'
    code: 'Roboto Mono'
  features:
    - navigation.tabs
    - navigation.sections
    - search.suggest
    - search.highlight
    - content.tabs.link
    - content.code.annotation
    - content.code.copy
markdown_extensions:
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.inlinehilite
  - pymdownx.snippets
  - pymdownx.superfences
  - admonition
  - pymdownx.details
  - pymdownx.superfences
  - attr_list
  - md_in_html