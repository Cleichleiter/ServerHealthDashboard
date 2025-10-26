## Server Health Dashboard

![PowerShell](https://img.shields.io/badge/PowerShell-7-blue?logo=powershell\&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Automation-success?logo=githubactions\&logoColor=white)
![Infrastructure as Code](https://img.shields.io/badge/IaC-Infrastructure%20as%20Code-lightgrey?logo=azuredevops)
![Status](https://img.shields.io/badge/Status-Active-brightgreen)

---

### Overview

The **Server Health Dashboard** is a PowerShell automation project that collects and reports on system health metrics from local or remote Windows servers.
It generates visually styled HTML, CSV, and JSON reports, which can be automatically built using GitHub Actions on a schedule or manually on demand.

This project demonstrates how Infrastructure as Code (IaC) and workflow automation can be combined to monitor and document environments consistently. It serves as a practical example for MSPs, system engineers, and DevOps professionals.

---

### Features

* Collects OS, uptime, disk space, latency, and service status
* Generates color-coded HTML dashboard with detailed tables
* Supports local and multi-server configuration via `servers.json`
* Automates execution with GitHub Actions (Windows runner)
* Uploads results as downloadable artifacts (HTML, CSV, JSON)
* Modular design, easily extendable for CPU, RAM, or Azure metrics

---

### Technology Stack

| Component             | Purpose                                       |
| --------------------- | --------------------------------------------- |
| PowerShell 7          | Core scripting and automation logic           |
| GitHub Actions (YAML) | Workflow scheduling and automation            |
| JSON                  | Configuration for server targets and services |
| HTML / CSS            | Visual reporting output                       |
| CSV / JSON            | Data export for analysis or ingestion         |

---

### How It Works

1. `ServerHealth.ps1` queries target systems (or localhost) using WMI and service APIs.
2. The script formats data into HTML, CSV, and JSON files under the `Output` directory.
3. The GitHub Actions workflow (`.github/workflows/server-health.yml`) runs the script on a Windows VM.
4. Reports are compressed, uploaded as artifacts, and optionally scheduled to run nightly.

---

### Folder Structure

```
ServerHealthDashboard/
│
├── Scripts/
│   └── ServerHealth.ps1
│
├── Output/                 # Generated reports (ignored by Git)
├── servers.json            # Config file with servers & services
├── .github/
│   └── workflows/
│       └── server-health.yml
└── .gitignore
```

---

### Security Note

This repository contains automation code only. It does not expose your local system, network, or credentials.

* SSH keys are used only for authenticating pushes to GitHub.
* GitHub Actions run inside isolated cloud VMs, not your personal computer.
* No secrets, tokens, or internal IPs are included.
* The PowerShell scripts only read system information; they do not open network ports or allow inbound connections.

This project demonstrates professional automation and reporting practices safely and securely.

---

### Example Output

The HTML report includes:

* Summary table of all servers
* Expandable per-server details
* Disk and service status with color-coded badges
* Exportable data formats (CSV, JSON)

---

### Future Enhancements

* Add CPU and memory usage tracking
* Integrate with Azure via `Get-AzVM -Status`
* Send HTML report by email or Teams webhook
* Publish to GitHub Pages for live dashboards
* Include Pester tests for data validation

---

### Run It Locally

You can generate a local report manually using PowerShell 7:

```powershell
cd C:\Repos\ServerHealthDashboard
pwsh .\Scripts\ServerHealth.ps1 -Verbose
```

The reports will appear under the `Output` folder as:

* `Report.html`
* `Report.csv`
* `Report.json`
* `ServerHealth.log`

---

### Author

**Cheri Leichleiter**
System Engineer | MSP Automation & Infrastructure
[LinkedIn Profile](https://www.linkedin.com/in/cheri-leichleiter-653349268/)






