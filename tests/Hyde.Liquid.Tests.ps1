Describe 'Hyde Liquid module' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $liquidModulePath = Join-Path -Path $projectRoot -ChildPath 'src\Liquid\Hyde.Liquid.psm1'
        Import-Module $liquidModulePath
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

    It 'supports for loops and forloop metadata' {
        $template = '{% for item in page.items %}[{{ forloop.index }}:{{ item }}{% if forloop.last %}:last{% endif %}]{% else %}[empty]{% endfor %}'
        $context = @{
            page = @{
                items = @('one', 'two')
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context
        $result | Should -Be '[1:one][2:two:last]'
    }

    It 'supports for else when a collection is empty' {
        $template = '{% for item in page.items %}[{{ item }}]{% else %}[empty]{% endfor %}'
        $context = @{
            page = @{
                items = @()
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context
        $result | Should -Be '[empty]'
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

    It 'supports custom tags and filters through a registry' {
        $registry = New-LiquidExtensionRegistry
        Register-LiquidTag -Registry $registry -Dialect 'JekyllLiquid' -Name 'seo' -Handler {
            param($Invocation)

            $site = & $Invocation.Helpers.ResolveVariable 'site'
            $page = & $Invocation.Helpers.ResolveVariable 'page'
            return "<title>$($page.title) | $($site.title)</title>"
        }
        Register-LiquidFilter -Registry $registry -Dialect 'JekyllLiquid' -Name 'surround' -Handler {
            param($Invocation)

            return "$($Invocation.Arguments[0])$($Invocation.InputObject)$($Invocation.Arguments[0])"
        }

        $template = '{% seo %} {{ page.title | surround: "[" }}'
        $context = @{
            site = @{
                title = 'Test Site'
            }
            page = @{
                title = 'Home'
            }
        }

        $result = Invoke-LiquidTemplate -Template $template -Context $context -Dialect 'JekyllLiquid' -Registry $registry
        $result | Should -Be '<title>Home | Test Site</title> [Home['
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
