# Contributing

## Workflow

1. Open an issue or find one you want to work on
2. Design a Pester test
3. Write code
4. Document code
5. Test
6. Create pull request

## Plugin Authoring

Plugin authoring guidance lives in [docs/PluginAuthoring.md](docs/PluginAuthoring.md).

For built-in plugins that have dependencies to install, run installation/setup directly from the plugin script:

```powershell
.\src\Plugins\libsass-converter.ps1 -Install
```

## Testing

Pester tests are available under `/tests`.

## Security Model

- Hyde is designed for trusted author workflows. Content rendered through Liquid and Markdown is not sanitized by Hyde.
- Generated output must remain inside the configured destination root. Changes that affect output path resolution must preserve this containment guarantee.
- Clean operations must remain conservative. Any change to clean logic must keep protections against deleting drive roots, site roots, or parent paths of source.
- `include_relative` behavior is intentionally scoped for post content under the matching `_posts` tree.

## Trust Boundaries

- Trusted: maintainers and contributors with repository write access.
- Conditionally trusted: site content authors. If content is untrusted, Hyde should not be used without an external sanitization step.
- High trust required: plugin code. Plugins execute as PowerShell code during build.
- Safe mode (`safe: true`) limits plugin loading to entries in `whitelist`; do not weaken this behavior in plugin-loading changes.
- Dependency installers (for example `libsass-converter -Install`) may download artifacts. Keep warnings clear and preserve user confirmation behavior for interactive installs.
