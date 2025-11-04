<#
Run tests with a safe default to avoid the common 'file does not exist' mistake.
Usage:
  # Run default (prefer test/widget_test.dart if present)
  ./scripts/run-tests.ps1

  # Run a specific test or pattern
  ./scripts/run-tests.ps1 test/some_test.dart
#>
param(
    [string]$TestPath = ''
)

Write-Host "Running flutter pub get..."
flutter pub get

if ([string]::IsNullOrWhiteSpace($TestPath)) {
    if (Test-Path -Path "test\widget_test.dart") {
        $TestPath = 'test/widget_test.dart'
    }
}

if (-not [string]::IsNullOrWhiteSpace($TestPath)) {
    Write-Host "Running flutter test $TestPath -r expanded"
    flutter test $TestPath -r expanded
} else {
    Write-Host "No specific test found; running full test suite"
    flutter test -r expanded
}
