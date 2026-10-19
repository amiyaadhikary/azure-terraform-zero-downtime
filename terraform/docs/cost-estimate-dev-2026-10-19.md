# Dev monthly cost estimate — Central India

Checked 2026-10-19 using Microsoft's Azure Retail Prices API, USD pay-as-you-go rates, and 730 hours/month. This is a known baseline for the current `dev.tfvars`, not a quote or a full invoice forecast.

| Resource / assumption | Rate | Monthly calculation | Estimate |
|---|---:|---:|---:|
| VMSS: 1 Linux `Standard_B2ts_v2` instance | $0.0112/hour | 0.0112 × 730 | $8.18 |
| PostgreSQL Flexible Server: `B_Standard_B1ms` (1 vCore) | $0.0245/hour | 0.0245 × 730 | $17.89 |
| PostgreSQL provisioned storage: 32 GiB | $0.131/GiB-month | 0.131 × 32 | $4.19 |
| Application Gateway Standard_v2 fixed charge | $0.28/hour | 0.28 × 730 | $204.40 |
| Application Gateway minimum capacity: 1 instance = 10 CUs | $0.008/CU-hour | 0.008 × 10 × 730 | $58.40 |
| NAT Gateway Standard/StandardV2 base charge | $0.045/hour | 0.045 × 730 | $32.85 |
| Two Standard IPv4 public IPs (Application Gateway and NAT) | $0.005/IP-hour | 0.005 × 2 × 730 | $7.30 |
| **Known baseline subtotal** |  |  | **$333.20/month** |

The subtotal excludes managed OS-disk charges, Storage capacity and transactions, NAT data processing ($0.045/GB), outbound bandwidth, PostgreSQL backup usage beyond the included allowance, Application Insights ingestion, and taxes. PostgreSQL backup storage is assumed to remain within its included allowance. The dev VMSS starts at one instance (autoscale 1–2) and App Gateway has its provider-required 1-2 capacity range. There is no Bastion in the dev profile.

## Prod monthly cost estimate — Central India (Resilient Profile)

Baseline for `prod.tfvars` assuming minimum 2 `Standard_D2s_v5` VMSS instances across Zones 1 & 2 (autoscale 2–6), `GP_Standard_D2s_v3` PostgreSQL Flexible Server with Zone-Redundant High Availability (primary + standby), 64 GiB storage, Application Gateway `Standard_v2`, and `StandardV2` NAT Gateway:

| Resource / assumption | Rate | Monthly calculation | Estimate |
|---|---:|---:|---:|
| VMSS: 2 Linux `Standard_D2s_v5` instances (min baseline) | $0.096/hour × 2 | 0.192 × 730 | $140.16 |
| PostgreSQL Flexible Server: `GP_Standard_D2s_v3` + Zone-Redundant HA (2× compute) | $0.178/hour × 2 | 0.356 × 730 | $259.88 |
| PostgreSQL provisioned storage: 64 GiB (primary + HA standby) | $0.131/GiB-month × 128 | 0.131 × 128 | $16.77 |
| Application Gateway Standard_v2 fixed charge | $0.28/hour | 0.28 × 730 | $204.40 |
| Application Gateway capacity: 1–2 instances (10 CUs baseline) | $0.008/CU-hour | 0.008 × 10 × 730 | $58.40 |
| NAT Gateway Standard/StandardV2 base charge | $0.045/hour | 0.045 × 730 | $32.85 |
| Two Standard IPv4 public IPs (Application Gateway and NAT) | $0.005/IP-hour | 0.005 × 2 × 730 | $7.30 |
| **Known Prod baseline subtotal (at min 2 VMs)** |  |  | **$719.76/month** |

*(If VMSS scales out to all 6 `Standard_D2s_v5` instances during sustained peak traffic, compute adds up to +$280.32/month.)*

Sources: [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), [Application Gateway pricing and capacity units](https://learn.microsoft.com/en-us/azure/application-gateway/understanding-pricing), [NAT Gateway SKU pricing](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-sku). Retail list rates do not account for subscription discounts, credits, or regional capacity.
