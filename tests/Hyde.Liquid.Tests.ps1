Describe 'Hyde Liquid module' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $liquidModulePath = Join-Path -Path $projectRoot -ChildPath 'src\Liquid\Hyde.Liquid.psm1'
        Import-Module $liquidModulePath -Force
    }

    It 'renders basic objects and filters' {
        $template = 'Hello {{ page.title | upcase }}'
        $context = @{
            page = @{
                title = 'home'
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context
        $result | Should -Be 'Hello HOME'
    }

    It 'renders assign and if tags' {
        $template = '{% assign greeting = "Hello" %}{% if page.title == "Home" %}{{ greeting }}, {{ page.title | downcase }}{% endif %}'
        $context = @{
            page = @{
                title = 'Home'
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context
        $result | Should -Be 'Hello, home'
    }

    It 'supports comment and raw tags' {
        $template = 'A{% comment %}ignore me{% endcomment %}B{% raw %}{{ untouched }}{% endraw %}'
        $context = @{}

        $result = Invoke-LiquidTemplate -Template $template -Context $context
        $result | Should -Be 'AB{{ untouched }}'
    }

    It 'supports include in the JekyllLiquid dialect with include variables' {
        $includeRoot = Join-Path -Path $TestDrive -ChildPath 'includes'
        [void](New-Item -Path $includeRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $includeRoot -ChildPath 'card.html') -Encoding UTF8 -Value 'Card: {{ include.title }} / {{ page.title }}'

        $template = 'Before {% include card.html title=page.title %} After'
        $context = @{
            page = @{
                title = 'Home'
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context -Dialect 'JekyllLiquid' -IncludeRoot $includeRoot
        $result | Should -Match 'Before Card: Home / Home\s+After'
    }

    It 'rejects include in the plain Liquid dialect' {
        $includeRoot = Join-Path -Path $TestDrive -ChildPath 'includes'
        [void](New-Item -Path $includeRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $includeRoot -ChildPath 'card.html') -Encoding UTF8 -Value 'Card'

        {
            Invoke-LiquidTemplate -Template '{% include card.html %}' -Context @{} -IncludeRoot $includeRoot
        } | Should -Throw -ExpectedMessage "*Liquid tag 'include' is not supported in the 'Liquid' dialect.*"
    }

    It 'supports Jekyll-specific URL and serialization filters in the JekyllLiquid dialect' {
        $template = '{{ "/assets/style.css" | relative_url }}|{{ "/assets/style.css" | absolute_url }}|{{ page.data | jsonify }}'
        $context = @{
            site = @{
                url     = 'https://example.com'
                baseurl = '/my-baseurl'
            }
            page = @{
                data = @{
                    title = 'Home'
                }
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context -Dialect 'JekyllLiquid'
        $result | Should -Be '/my-baseurl/assets/style.css|https://example.com/my-baseurl/assets/style.css|{"title":"Home"}'
    }

    It 'rejects Jekyll-specific filters in the plain Liquid dialect' {
        {
            Invoke-LiquidTemplate -Template '{{ "/assets/style.css" | relative_url }}' -Context @{ site = @{ baseurl = '/my-baseurl' } }
        } | Should -Throw -ExpectedMessage "*Liquid filter 'relative_url' is not supported in the 'Liquid' dialect.*"
    }

    It 'reports unsupported dialect values' {
        {
            Invoke-LiquidTemplate -Template 'Hello' -Context @{} -Dialect 'Liquid-Next'
        } | Should -Throw -ExpectedMessage "*Liquid dialect 'Liquid-Next' is not supported yet.*"
    }
}
