# Hyde SEO Tag Plugin
## about_Hyde_Plugin_SEO-Tag


# SHORT DESCRIPTION
Guidance for using Hyde's built-in seo-tag plugin.

# LONG DESCRIPTION
The built-in `seo-tag` plugin provides a Hyde equivalent of Jekyll SEO Tag behavior
through a Liquid tag implementation.

Enable the plugin in `_config.yml`:

```yaml
plugins:
  - jekyll-seo-tag
```

Render tags in a layout or page:

```liquid
{% seo %}
```

The plugin generates:

- `<title>`
- `<meta name="description">`
- `<link rel="canonical">`
- Open Graph tags (`og:*`)
- Twitter card tags (`twitter:*`)
- Facebook tags (`fb:*` and `article:publisher`)
- JSON-LD (`application/ld+json`)

## Canonical URL Behavior

By default, canonical URL is derived from page URL metadata and site URL settings.

Canonical URL selection order:

1. `page.canonical_url` (front matter override)
2. computed URL from `site.url`, optional `site.baseurl`, and page URL

Example page-level override:

```yaml
---
title: Canonical Example
canonical_url: https://example.org/articles/canonical-source
---
```

## Disabling Canonical Link Output

To disable only the `<link rel="canonical">` tag for a specific template invocation,
pass an inline option to the tag:

```liquid
{% seo canonical=false %}
```

This suppresses canonical link output while preserving the rest of SEO output,
including `<meta property="og:url">`.

## Notes

- `canonical=false` is tag-level behavior and can be applied selectively.
- `canonical_url` is front matter behavior and customizes the URL value itself.
- If no override is provided, canonical URL is computed from site and page metadata.
