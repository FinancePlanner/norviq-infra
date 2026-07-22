locals {
  # Each rule: Loki instant query (A) -> reduce last (B) -> threshold (C).
  # Queries mirror docs/runbook-tax.md "Grafana Cloud / Loki alert queries".
  tax_rules = {
    tax-report-generation-failed = {
      title     = "Tax report generation failed"
      expr      = "sum by (namespace) (count_over_time({namespace=~\"staging|production\", app=\"api\"} |= \"tax.report generation failed\" [5m]))"
      window_s  = 300
      threshold = 0 # fire on any match in 5m
      severity  = "critical"
      summary   = "Tax report generation failures in {{ $labels.namespace }} in the last 5m."
    }
    tax-projection-poll-failed = {
      title     = "Tax projection poll failing"
      expr      = "sum by (namespace) (count_over_time({namespace=~\"staging|production\", app=\"api\"} |= \"tax.projection poll failed\" [15m]))"
      window_s  = 900
      threshold = 3 # fire on >3 matches in 15m
      severity  = "warning"
      summary   = "More than 3 tax projection poll failures in {{ $labels.namespace }} in the last 15m."
    }
    tax-report-cleanup-retry-failed = {
      title     = "Tax report cleanup / retry exhaustion"
      expr      = "sum by (namespace) (count_over_time({namespace=~\"staging|production\", app=\"api\"} |~ \"tax.report|TaxReportCleanup|retry\" |= \"failed\" [15m]))"
      window_s  = 900
      threshold = 0
      severity  = "warning"
      summary   = "Tax report cleanup or retry-exhaustion failures in {{ $labels.namespace }} in the last 15m."
    }
    api-crash-or-credential-failure = {
      title     = "API crash / credential / PVC failure"
      expr      = "sum by (namespace) (count_over_time({namespace=~\"staging|production\", app=\"api\"} |~ \"DATABASE_USERNAME must not|Abort.500|CrashLoop\" [5m]))"
      window_s  = 300
      threshold = 0
      severity  = "critical"
      summary   = "API crash, credential validation, or PVC failure logged in {{ $labels.namespace }} in the last 5m."
    }
  }
}

resource "grafana_folder" "tax_alerts" {
  title = "Norviq Tax"
}

resource "grafana_rule_group" "tax_log_alerts" {
  name             = "tax-log-alerts"
  folder_uid       = grafana_folder.tax_alerts.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = local.tax_rules
    content {
      name           = rule.value.title
      condition      = "C"
      no_data_state  = "OK"
      exec_err_state = "Error"
      for            = "0s"

      annotations = {
        summary = rule.value.summary
        runbook = "norviq-infra/docs/runbook-tax.md"
      }

      labels = {
        severity = rule.value.severity
        team     = "norviq"
        feature  = "tax"
      }

      data {
        ref_id         = "A"
        datasource_uid = var.loki_datasource_uid
        relative_time_range {
          from = rule.value.window_s
          to   = 0
        }
        model = jsonencode({
          refId     = "A"
          expr      = rule.value.expr
          queryType = "instant"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          refId      = "B"
          type       = "reduce"
          expression = "A"
          reducer    = "last"
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          refId      = "C"
          type       = "threshold"
          expression = "B"
          conditions = [{
            evaluator = {
              type   = "gt"
              params = [rule.value.threshold]
            }
          }]
        })
      }
    }
  }
}
