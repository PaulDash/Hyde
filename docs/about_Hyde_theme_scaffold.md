# about_Hyde_theme_scaffold

`Hyde New-Theme` creates a starting point for authoring Hyde themes without adding a full theme-install workflow to Hyde itself.

## Scaffold Modes

### Default Previewable Mode

The default scaffold is a small buildable preview site. It gives you the reusable theme pieces plus an `index.md` page that uses the generated `default` layout.

Generated files:

```text
theme/
  _config.yml
  _layouts/
    default.html
  _includes/
    head.html
    site-header.html
  _sass/
    _theme.scss
  assets/
    css/
      site.scss
  index.md
```

### Portable Mode

Use `-Portable` when you want a reusable package-style scaffold without sample content pages.

Generated files:

```text
theme/
  _config.yml
  _layouts/
    default.html
  _includes/
    head.html
    site-header.html
  _sass/
    _theme.scss
  assets/
    css/
      site.scss
```

## Why `_sass` and `site.scss`

Hyde already defaults `sass.sass_dir` to `_sass`, and the built-in `libsass-converter` plugin compiles `.scss` files in the static output tree. The scaffold keeps the emitted stylesheet in `assets/css/site.scss` and shared styling tokens in `_sass/_theme.scss`.

The generated Sass uses classic `@import` syntax intentionally. Hyde's current Sass path is LibSass-based, so modern Dart Sass module syntax is not the right default scaffold yet.

## Usage

Create a previewable theme scaffold:

```powershell
Import-Module .\src\Hyde.psd1
Hyde New-Theme .\mytheme
```

Create a portable theme scaffold:

```powershell
Import-Module .\src\Hyde.psd1
New-StaticTheme -Destination .\mytheme -Portable
```

## Notes

- This command creates files only. It does not install, apply, or distribute themes.
- The default previewable scaffold is the best fit when you want an immediate place to test layout and styling changes.
- The portable scaffold is the better fit when you want to copy the theme structure into another site or package it for reuse.