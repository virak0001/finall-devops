import org.jenkinsci.plugins.workflow.steps.FlowInterruptedException

// One report for every check a build runs on its code and its image —
// security-report.txt, archived on every build, passed or failed:
//
//   RESULT          one line per check: passed, blocked, or never ran
//   1 Secrets       Gitleaks   committed credentials            Secret scan
//   2 Code          SonarQube  quality gate, issues, hotspots   Quality gate
//   3 Dependencies  Trivy      the lockfiles                    Security scan
//   4 Image         Trivy      base image and OS packages       Security scan
//
// Each stage leaves its raw result in the workspace, and write() reads them
// all at the end, from post { always } — so a build that stops at the quality
// gate still gets a report, saying which checks never ran. SonarQube's
// findings live on its server, not in the workspace: sonar() fetches them
// through its Web API right after the gate and leaves them in .platform/.
//
// Nothing here can fail a build or hide why it failed. A part that cannot be
// read says so in the report instead.
//
//   securityReport.sonar(qg.status)          Quality gate stage
//   securityReport.write(gate: 'CRITICAL')   post { always }

// ─── SonarQube ───────────────────────────────────────────────────────────────

void sonar(String gateStatus) {
  String summary = null
  String body = null
  try {
    // envOnly: the server's URL and its token (SONAR_AUTH_TOKEN — the user
    // token Jenkins is configured with; a service's project-analysis token
    // may analyse but not read issues), without registering a second analysis
    // on the build.
    withSonarQubeEnv(installationName: 'SonarQube', envOnly: true) {
      Map task = properties(readFile('.scannerwork/report-task.txt'))
      String key = task.projectKey
      String analysis = sonarApi("/api/ce/task?id=${enc(task.ceTaskId)}", false)?.task?.analysisId

      // This analysis' gate, not the project's latest: develop and testing
      // share one SonarQube project and can analyse at the same time.
      Map gate = sonarApi('/api/qualitygates/project_status?' +
                          (analysis ? "analysisId=${enc(analysis)}" : "projectKey=${enc(key)}"), false)
      String open = "componentKeys=${enc(key)}&resolved=false&ps=500"
      Map issues = sonarApi("/api/issues/search?${open}", false)
      Map fresh = sonarApi("/api/issues/search?${open}&inNewCodePeriod=true", false)
      Map hotspots = sonarApi("/api/hotspots/search?project=${enc(key)}&status=TO_REVIEW&ps=500", true)
      Map measures = sonarApi("/api/measures/component?component=${enc(key)}" +
                              '&metricKeys=coverage,duplicated_lines_density,ncloc', true)

      List r = renderSonar(key, publicSonarUrl(env.JENKINS_URL, env.SONAR_HOST_URL),
                           gate, issues, fresh, hotspots, measures)
      summary = r[0]
      body = r[1]
    }
  } catch (FlowInterruptedException e) {
    throw e
  } catch (e) {
    String status = gateStatus == 'OK' ? '✓|quality gate passed' : "✗|quality gate ${gateStatus ?: 'unknown'}"
    summary = "${status} — details unavailable"
    body = "Quality gate: ${gateStatus ?: 'unknown'}\n" +
           "The issues could not be read from SonarQube: ${e.message}\n"
  }
  writeFile file: '.platform/sonar.summary', text: summary
  writeFile file: '.platform/sonar.txt', text: body
}

// GET one SonarQube Web API path as JSON. Optional parts return null when the
// server will not answer; required ones fail sonar() into its fallback.
Map sonarApi(String path, boolean optional) {
  String endpoint = path.tokenize('?')[0]
  // No `sh -x`: its trace would print the token.
  String out = sh(label: "SonarQube ${endpoint}", returnStdout: true, script: '#!/bin/sh\n' +
    'curl -sS --fail --max-time 30 ${SONAR_AUTH_TOKEN:+-u "$SONAR_AUTH_TOKEN:"} "${SONAR_HOST_URL%/}' + path + '" || true')
  if (!out?.trim()) {
    if (optional) { return null }
    error("SonarQube did not answer ${endpoint}")
  }
  return (Map) parseJson(out)
}

// ─── The report ──────────────────────────────────────────────────────────────

void write(Map opts) {
  try {
    Map d = [
      gate         : opts.gate ?: 'CRITICAL',
      imageOrigin  : opts.imageOrigin,
      service      : env.SERVICE,
      team         : env.TEAM,
      branch       : env.BRANCH_NAME + (env.CHANGE_ID ? " (PR #${env.CHANGE_ID})" : ''),
      commit       : env.SHORT_SHA ?: env.GIT_COMMIT?.take(7),
      version      : env.VERSION,
      imageTag     : env.IMAGE_TAG,
      alreadyBuilt : env.ALREADY_BUILT == 'true',
      scannedImage : env.SCAN_IMAGE,
      buildUrl     : env.BUILD_URL,
      buildNumber  : env.BUILD_NUMBER,
      result       : currentBuild.currentResult,
    ]
    Map files = ['gitleaks'    : 'gitleaks-report.json',
                 'sonarSummary': '.platform/sonar.summary',
                 'sonar'       : '.platform/sonar.txt',
                 'dependencies': 'trivy-dependencies.txt',
                 'image'       : 'trivy-image.txt']
    for (String k : files.keySet()) {
      d[k] = fileExists(files[k]) ? readFile(files[k]) : null
    }

    List r = render(d)
    writeFile file: 'security-report.txt', text: r[0]
    archiveArtifacts artifacts: 'security-report.txt', allowEmptyArchive: true
    echo "${r[1]}\nFull report: ${env.BUILD_URL ?: ''}artifact/security-report.txt"
  } catch (FlowInterruptedException e) {
    throw e
  } catch (e) {
    echo "security-report.txt could not be written: ${e.message}"
  }
}

// "blocking: N", the Trivy report template's last line. -1 when it is missing.
@NonCPS
int blocking(String report) {
  def m = (report ?: '') =~ /(?m)^blocking: (\d+)\s*$/
  return m.find() ? (m.group(1) as int) : -1
}

// [whole report, its header + RESULT for the console]
@NonCPS
List render(Map d) {
  int width = 110
  String notRun = d.result in ['FAILURE', 'ABORTED'] ? 'not run — the build stopped before it' : 'not run'
  String gate = (d.gate as String).replace(',', '/')

  List secrets = gitleaksPart(d.gitleaks, notRun)
  List code = d.sonarSummary == null
    ? ['–', notRun, notRun]
    : [d.sonarSummary.tokenize('|')[0], d.sonarSummary.substring(d.sonarSummary.indexOf('|') + 1), d.sonar ?: '']
  List deps = trivyPart(d.dependencies, gate, notRun)
  List image = d.image == null && d.alreadyBuilt
    ? ['–', "skipped — ${d.imageOrigin ?: 'already in ECR'}; scanned by the build that made it", '']
    : trivyPart(d.image, gate, notRun)
  image[2] = image[2] ?: image[1]
  if (d.image != null && d.scannedImage) {
    image[2] = "Scanned from ECR, not rebuilt: ${d.scannedImage}\n" +
               "— the image ${d.imageTag} names, against today's vulnerability database.\n\n" + image[2]
  }

  List rows = [['Secrets', 'Gitleaks', secrets], ['Code', 'SonarQube', code],
               ['Dependencies', 'Trivy', deps], ['Image', 'Trivy', image]]

  StringBuilder head = new StringBuilder()
  head << ('═' * width) << '\n'
  head << " Security report — ${d.service ?: '?'} #${d.buildNumber ?: '?'} ${d.imageTag ?: ''}\n"
  head << ('═' * width) << '\n'
  head << " service   ${d.service ?: '?'}${d.team ? " (team ${d.team})" : ''}\n"
  head << " commit    ${d.commit ?: '?'} on ${d.branch ?: '?'}${d.version ? " · version ${d.version}" : ''}\n"
  if (d.imageTag) { head << " image     ${d.imageTag}${d.imageOrigin ? " — ${d.imageOrigin}" : ''}\n" }
  head << " build     ${d.buildUrl ?: '?'} — ${d.result}\n"
  head << " written   ${new Date().format("yyyy-MM-dd HH:mm 'UTC'", TimeZone.getTimeZone('UTC'))}\n\n"
  head << " RESULT    the build stops on a committed secret, a failed quality gate,\n"
  head << "           or a fixable ${gate} vulnerability (✗)\n"
  rows.each { r -> head << sprintf('   %-2s %-13s %-10s %s\n', r[2][0], r[0], r[1], r[2][1]) }

  StringBuilder all = new StringBuilder(head)
  rows.eachWithIndex { r, i ->
    String title = "══ ${i + 1}  ${r[0]} · ${r[1]} "
    all << '\n' << title << ('═' * Math.max(4, width - title.length())) << '\n'
    all << (r[2][2] as String).trim() << '\n'
  }
  return [all.toString(), head.toString()]
}

// [mark, one-line result, section]
@NonCPS
List gitleaksPart(String json, String notRun) {
  if (json == null) { return ['–', notRun, notRun] }
  List found
  try {
    found = json.trim() ? (List) parseJson(json) : []
  } catch (ignored) {
    return ['?', 'gitleaks-report.json is unreadable', 'gitleaks-report.json is unreadable — see it in the build artifacts.']
  }
  if (!found) { return ['✓', 'none found', 'No secrets found.'] }

  StringBuilder s = new StringBuilder()
  s << "${found.size()} committed secret(s). Rotate each one first — it is in git history and must be\n"
  s << "treated as leaked — then rewrite the history, or allowlist the fingerprint in .gitleaksignore.\n\n"
  s << sprintf('%-26s %-50s %-9s %s\n', 'RULE', 'WHERE', 'COMMIT', 'DESCRIPTION')
  found.each { f ->
    s << sprintf('%-26s %-50s %-9s %s\n', cut(f.RuleID, 26), cut("${f.File}:${f.StartLine}", 50),
                 ((f.Commit ?: '') as String).take(7), cut(f.Description, 60))
  }
  return ['✗', "${found.size()} committed secret(s)", s.toString()]
}

@NonCPS
List trivyPart(String text, String gate, String notRun) {
  if (text == null) { return ['–', notRun, notRun] }
  int n = blocking(text)
  String body = text.replaceAll(/(?m)^blocking: \d+\s*$/, '').trim()
  def m = text =~ /(?m)^Summary:\s*(.*)$/
  String found = m.find() ? m.group(1).trim() : 'no vulnerabilities'
  if (n < 0) { return ['?', 'report has no blocking line — template broken', body] }
  if (n > 0) { return ['✗', "${n} fixable ${gate} — upgrade, or accept in .trivyignore · ${found}", body] }
  return ['✓', "none blocking · ${found}", body]
}

// [summary "mark|text", section]
@NonCPS
List renderSonar(String key, String url, Map gate, Map issues, Map fresh, Map hotspots, Map measures) {
  List order = ['BLOCKER', 'HIGH', 'MEDIUM', 'LOW', 'INFO']
  // Standard-experience severities and types, for issues without impacts.
  Map legacy = [BLOCKER: 'BLOCKER', CRITICAL: 'HIGH', MAJOR: 'MEDIUM', MINOR: 'LOW', INFO: 'INFO']
  Map types = [BUG: 'Reliability', VULNERABILITY: 'Security', CODE_SMELL: 'Maintainability']
  Map cmp = [GT: '>', LT: '<']

  Map status = gate?.projectStatus ?: [:]
  boolean passed = status.status == 'OK'
  List conditions = status.conditions ?: []
  List failed = conditions.findAll { it.status == 'ERROR' }

  Set newKeys = ((fresh?.issues ?: []).collect { it.key }) as Set
  List rows = (issues?.issues ?: []).collect { i ->
    Map worst = (i.impacts ?: []).min { order.indexOf(it.severity) }
    [isNew  : newKeys.contains(i.key),
     sev    : worst ? worst.severity : (legacy[i.severity] ?: 'INFO'),
     quality: worst ? (worst.softwareQuality as String).toLowerCase().capitalize() : (types[i.type] ?: ''),
     rule   : i.rule ?: '',
     where  : where(i.component, key, i.line),
     message: i.message ?: '']
  }
  rows.sort { a, b -> (b.isNew <=> a.isNew) ?: (order.indexOf(a.sev) <=> order.indexOf(b.sev)) }
  int total = (issues?.paging?.total ?: issues?.total ?: rows.size()) as int
  int newTotal = (fresh?.paging?.total ?: fresh?.total ?: newKeys.size()) as int
  List spots = hotspots?.hotspots ?: []
  int spotTotal = (hotspots?.paging?.total ?: spots.size()) as int

  String verdict = passed ? '✓|quality gate passed'
    : "✗|quality gate FAILED — " + (failed.collect { "${it.metricKey} ${it.actualValue} (${cmp[it.comparator] ?: it.comparator} ${it.errorThreshold})" }.join(', ') ?: (status.status ?: 'no status'))
  String summary = "${verdict} · ${total} open issue(s), ${newTotal} new · " +
                   (hotspots == null ? 'hotspots unknown' : "${spotTotal} hotspot(s) to review")

  StringBuilder s = new StringBuilder()
  s << "Quality gate  ${passed ? 'PASSED' : 'FAILED'}    ${url}/dashboard?id=${enc(key)}\n"
  conditions.each { c ->
    s << sprintf('  %-2s %-34s %-10s fails when %s %s\n', c.status == 'ERROR' ? '✗' : '✓', c.metricKey,
                 c.actualValue ?: '–', cmp[c.comparator] ?: c.comparator, c.errorThreshold)
  }
  Map m = ((measures?.component?.measures ?: []).collectEntries { [(it.metric): it.value] })
  List facts = []
  if (m.coverage != null) { facts << "coverage ${m.coverage}%" }
  if (m.duplicated_lines_density != null) { facts << "duplication ${m.duplicated_lines_density}%" }
  if (m.ncloc != null) { facts << "${m.ncloc} lines of code" }
  if (facts) { s << '  ' << facts.join(' · ') << '\n' }

  s << "\nOpen issues   ${total} · ${newTotal} new in this version — new code is what the gate judges\n"
  List counts = order.collect { o -> [o, rows.count { it.sev == o }] }.findAll { it[1] > 0 }
  if (counts) { s << '              ' << counts.collect { "${it[0]} ${it[1]}" }.join(' · ') << '\n' }
  if (rows) {
    int shown = Math.min(rows.size(), 50)
    s << '\n' << sprintf('%-4s %-8s %-16s %-24s %-40s %s\n', 'NEW', 'SEVERITY', 'QUALITY', 'RULE', 'WHERE', 'MESSAGE')
    rows.take(shown).each { r ->
      s << sprintf('%-4s %-8s %-16s %-24s %-40s %s\n', r.isNew ? 'new' : '', r.sev, cut(r.quality, 16),
                   cut(r.rule, 24), cut(r.where, 40), cut(r.message, 90))
    }
    if (total > shown) {
      s << "(the first ${shown} of ${total}, new first — all of them: ${url}/project/issues?id=${enc(key)}&resolved=false)\n"
    }
  }

  if (hotspots != null) {
    s << "\nSecurity hotspots to review   ${spotTotal}\n"
    if (spots) {
      s << sprintf('%-11s %-22s %-40s %s\n', 'PROBABILITY', 'CATEGORY', 'WHERE', 'MESSAGE')
      spots.sort { a, b -> ['HIGH', 'MEDIUM', 'LOW'].indexOf(a.vulnerabilityProbability) <=>
                           ['HIGH', 'MEDIUM', 'LOW'].indexOf(b.vulnerabilityProbability) }
           .take(50).each { h ->
        s << sprintf('%-11s %-22s %-40s %s\n', h.vulnerabilityProbability ?: '', cut(h.securityCategory, 22),
                     cut(where(h.component, key, h.line), 40), cut(h.message, 90))
      }
      s << "(review them: ${url}/security_hotspots?id=${enc(key)})\n"
    }
  }
  return [summary, s.toString()]
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// "core-service:src/main.ts", 12 → "src/main.ts:12"
@NonCPS
String where(Object component, String key, Object line) {
  String path = (component ?: '') as String
  if (key && path.startsWith("${key}:")) { path = path.substring(key.length() + 1) }
  return line ? "${path}:${line}" : path
}

// Jenkins and SonarQube share the box, SonarQube on :9000. SONAR_HOST_URL is
// the compose-network name (http://sonarqube:9000), useless in a browser.
@NonCPS
String publicSonarUrl(String jenkinsUrl, String hostUrl) {
  def m = (jenkinsUrl ?: '') =~ /^(https?:\/\/[^\/:]+)/
  return m.find() ? "${m.group(1)}:9000" : (hostUrl ?: '').replaceAll(/\/+$/, '')
}

@NonCPS
Map properties(String text) {
  Map p = [:]
  (text ?: '').readLines().each { l ->
    int i = l.indexOf('=')
    if (i > 0 && !l.startsWith('#')) { p[l.substring(0, i).trim()] = l.substring(i + 1).trim() }
  }
  return p
}

@NonCPS
Object parseJson(String text) {
  return new groovy.json.JsonSlurperClassic().parseText(text)
}

@NonCPS
String enc(Object s) {
  return URLEncoder.encode((s ?: '') as String, 'UTF-8')
}

@NonCPS
String cut(Object s, int n) {
  String t = ((s ?: '') as String).replaceAll(/\s+/, ' ')
  return t.length() <= n ? t : t.take(n - 1) + '…'
}
