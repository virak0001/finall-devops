{{- /*
  Trivy report, worst first: CRITICAL → HIGH → MEDIUM → LOW → UNKNOWN.
  Used by servicePipeline's Security scan as
    trivy convert --format template --template @.platform/trivy-report.tpl <scan.json>

  __GATE__ is replaced before use with the severities that fail the build,
  e.g. "CRITICAL" "HIGH". A finding blocks (✗) when its severity is in the
  gate and a fixed version exists — the same rule as --ignore-unfixed.

  The last line, "blocking: N", is what the pipeline reads to pass or fail.
*/ -}}
{{- $gate := list __GATE__ -}}
{{- $order := list "CRITICAL" "HIGH" "MEDIUM" "LOW" "UNKNOWN" -}}
{{- $total := 0 -}}
{{- $blocking := 0 -}}
{{- range $r := . }}{{ range $r.Vulnerabilities }}
  {{- $total = add $total 1 }}
  {{- if and (has .Severity $gate) .FixedVersion }}{{ $blocking = add $blocking 1 }}{{ end }}
{{- end }}{{ end -}}

{{- if eq $total 0 }}
No vulnerabilities found.
{{- else }}
Summary:
{{- range $sev := $order }}
  {{- $n := 0 }}
  {{- range $r := $ }}{{ range $r.Vulnerabilities }}{{ if eq .Severity $sev }}{{ $n = add $n 1 }}{{ end }}{{ end }}{{ end }}
  {{- if gt $n 0 }} {{ $sev }} {{ $n }} ·{{ end }}
{{- end }} total {{ $total }}
{{ range $sev := $order }}
  {{- $n := 0 }}
  {{- range $r := $ }}{{ range $r.Vulnerabilities }}{{ if eq .Severity $sev }}{{ $n = add $n 1 }}{{ end }}{{ end }}{{ end }}
  {{- if gt $n 0 }}
── {{ $sev }} ({{ $n }}) {{ repeat (sub 60 (len $sev) | int) "─" }}
{{ printf "%-5s %-20s %-28s %-16s %-22s %-26s %s" "BLOCK" "ID" "PACKAGE" "INSTALLED" "FIXED IN" "WHERE" "TITLE" }}
{{- range $r := $ }}{{ range $r.Vulnerabilities }}{{ if eq .Severity $sev }}
{{ printf "%-5s %-20s %-28s %-16s %-22s %-26s %s"
     (ternary "  ✗" "" (and (has .Severity $gate) (ne .FixedVersion "")))
     .VulnerabilityID
     (trunc 28 .PkgName)
     (trunc 16 .InstalledVersion)
     (trunc 22 (default "no fix yet" .FixedVersion))
     (trunc 26 $r.Target)
     (trunc 70 (default "" .Title)) }}
{{- end }}{{ end }}{{ end }}
{{ end }}
{{- end }}
{{- end }}
blocking: {{ $blocking }}
