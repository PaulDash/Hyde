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
