#!/usr/bin/env python3
"""
FinOps Cost Reporter for cloudops_control_plane
Fetches AWS Cost Explorer data for the last 30 days.
Generates:
- cost-report.json (detailed)
- monthly.md (human-readable report)
Fails if total cost > $30 (budget alert).
"""

import boto3
import json
import sys
from datetime import datetime, timedelta

def generate_monthly_md(result, report_date):
    """Create markdown report from cost data."""
    lines = [
        f"# Monthly FinOps Report",
        f"",
        f"**Month:** {report_date.strftime('%B %Y')}",
        f"**Report Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"",
        f"## Cost Summary",
        f"",
        f"| Category | Actual | Budget | Variance |",
        f"|----------|--------|--------|----------|",
    ]
    # Break down services into categories (approximate)
    compute = sum(s['cost_usd'] for s in result['services'] if 'EKS' in s['service'] or 'EC2' in s['service'])
    database = sum(s['cost_usd'] for s in result['services'] if 'RDS' in s['service'])
    networking = sum(s['cost_usd'] for s in result['services'] if 'NAT' in s['service'] or 'ELB' in s['service'])
    other = result['total_cost_usd'] - compute - database - networking
    
    lines.append(f"| Compute (EKS/EC2) | ${compute:.2f} | $15.00 | ${compute - 15:.2f} |")
    lines.append(f"| Database (RDS) | ${database:.2f} | $12.00 | ${database - 12:.2f} |")
    lines.append(f"| Networking | ${networking:.2f} | $3.00 | ${networking - 3:.2f} |")
    lines.append(f"| **Total** | **${result['total_cost_usd']:.2f}** | **$30.00** | **${result['total_cost_usd'] - 30:.2f}** |")
    lines.append(f"")
    lines.append(f"## Top Cost Drivers")
    for s in sorted(result['services'], key=lambda x: x['cost_usd'], reverse=True)[:5]:
        lines.append(f"- **{s['service']}**: ${s['cost_usd']:.2f}")
    lines.append(f"")
    lines.append(f"## Daily Cost Trend")
    lines.append(f"```")
    for day in result['daily_costs'][-7:]:  # last 7 days
        lines.append(f"{day['date']}: ${day['cost']:.2f}")
    lines.append(f"```")
    lines.append(f"")
    lines.append(f"## Action Items")
    if result['total_cost_usd'] > 30:
        lines.append(f"- [ ] 🔴 **Budget overrun** – investigate and scale down")
    else:
        lines.append(f"- [ ] ✅ Within budget – monitor next month")
    lines.append(f"- [ ] Review EBS snapshots and idle resources")
    lines.append(f"")
    lines.append(f"*Automated report – do not edit manually.*")
    
    with open('finops/reports/monthly.md', 'w') as f:
        f.write('\n'.join(lines))

def main():
    client = boto3.client('ce')
    end = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    start = end - timedelta(days=30)

    response = client.get_cost_and_usage(
        TimePeriod={'Start': start.strftime('%Y-%m-%d'), 'End': end.strftime('%Y-%m-%d')},
        Granularity='DAILY',
        Metrics=['BlendedCost'],
        GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
    )

    total_cost = 0.0
    daily_costs = []
    service_breakdown = {}

    for day in response['ResultsByTime']:
        day_total = float(day['Total']['BlendedCost']['Amount'])
        total_cost += day_total
        daily_costs.append({'date': day['TimePeriod']['Start'], 'cost': round(day_total, 2)})
        for item in day.get('Groups', []):
            service = item['Keys'][0]
            cost = float(item['Metrics']['BlendedCost']['Amount'])
            service_breakdown[service] = service_breakdown.get(service, 0) + cost

    result = {
        'period_start': start.strftime('%Y-%m-%d'),
        'period_end': end.strftime('%Y-%m-%d'),
        'total_cost_usd': round(total_cost, 2),
        'daily_costs': daily_costs,
        'services': [{'service': k, 'cost_usd': round(v, 2)} for k, v in service_breakdown.items()]
    }

    # Write JSON report
    with open('cost-report.json', 'w') as f:
        json.dump(result, f, indent=2)

    # Generate monthly markdown report
    generate_monthly_md(result, start)

    # Budget alert
    if total_cost > 30:
        print(f"❌ BUDGET EXCEEDED: ${total_cost:.2f} > $30.00")
        sys.exit(1)
    else:
        print(f"✅ Budget OK: ${total_cost:.2f} / $30.00")
        sys.exit(0)

if __name__ == "__main__":
    main()