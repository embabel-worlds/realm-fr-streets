---
name: fr-streets
description: Watch French places and answer questions about them and about France — recorded crime (SSMSI, commune and departement), income, poverty and INEQUALITY (Filosofi), census age and immigration, density, mayors and deputies — rank, trend and model crime ACROSS communes or departements. Use for any question about a French town, commune, arrondissement, departement, or crime in France.
---

# fr-streets

## Views first
| Question | View |
|---|---|
| What's this place like? | `FrPlaceDossier` |
| Crime at my places, vs before COVID | `FrCrimeAtMyPlaces` (year, baseline) |
| One indicator over 10 years at a place | `FrCrimeTrendAtPlace` (place, indicator) |
| Is crime X rising in France? | `FrNationalTrend` (indicator) — complete, homicides included |
| Worst departements for X | `FrDepartementLeague` (indicator, year) — nothing suppressed |
| Worst communes for X | `FrCrimeLeague` (indicator, year, minPopulation, limit) |
| Where did X rise / fall most? | `FrCrimeMovers` (indicator, fromYear, toYear, minPopulation, minCount) |
| What predicts X across departements? | `FrDepartementModel` (+ switches incl. inequality), `FrDepartementPredictorsOneByOne`, `FrDepartementRows` |
| What predicts X across communes? | `FrWhatBestPredictsCrime`, `FrCrimePredictorsOneByOne`, `FrCommunesRanked`, `FrModelRows` |
| Who represents it | `FrDeputiesAtMyPlaces`, mayor in the dossier |
| France against its neighbours | `EuBorderRegions` (border or 'all') — regions both sides, their NUTS 2 parents, countries |
| How a commune voted in the 2024 European election | `(c:FrCommune {code})-[:HAS_EURO24]->(v:FrEuroVote)` — share of list N = vN / expressed |
| Census unemployment, qualifications | `(m:FrMelodiPlace {geo})-[:HAS_WORK]->(w:FrWork)`, `-[:HAS_EDUCATION]->(e:FrEducation)` |

Indicators are the SSMSI's French labels, verbatim — e.g. `Cambriolages de logement` (burglary),
`Violences physiques hors cadre familial`, `Vols violents sans arme`, `Trafic de stupéfiants`.
Departement views also take `Homicides`, `Tentatives d'homicide`, `Usage de stupéfiants (hors AFD)`.

**Prefer the departement level for "what predicts" questions.** It suppresses nothing (the commune
base hides small communes, which biases a commune fit toward the places with the most crime), and
only there does INSEE publish inequality (Gini). The commune level is for "which towns".

## Watching a place
Resolve to the INSEE code — never key on the postal code (01400 covers 10 communes; Paris has 21).
1. `gateway.frAdresse.frGeocode({ q: '<text>', type: 'municipality', limit: '1' })` →
   `features[0].properties.citycode`, `.city`, `.postcode`, `geometry.coordinates` [lon, lat].
2. Departement = first 2 chars of the code (3 for 97x overseas; `2A`/`2B` Corsica).
3. `melodiGeo` = `2025-COM-<code>`; for a Paris/Lyon/Marseille arrondissement
   (751xx, 132xx, 6938x) use `2025-ARM-<code>`.
4. `gateway.repository.createEntry({ type: 'FrPlace', data: { name, inseeCode, melodiGeo, commune, departement, postcode, latitude, longitude } })`.

## Saying it honestly
- A suppressed commune figure (`published = 'ndiff'`) is NOT zero and NOT the departement average.
- Recorded crime counts offences where they were RECORDED; it also measures reporting and
  policing. Drug offences are almost all police-initiated — a surge is usually an operation.
  Rises in domestic and sexual violence can be more reporting.
- Model output is association across places. Never phrase a beta as a statement about a group
  of people, and never as "risk of crime here". The immigrant share is an area measure; France
  has no ethnic statistics. At departement level, with ~96 rows and correlated predictors, betas
  are noisy: report the pattern and the solo-vs-together contrast, not second decimals.
- No street-level or point crime exists in French open data; don't imply it.
- Election lists are named by their panel number, the ministry's own title and its nuance code
  (5 LRN, 27 LUG, 11 LENS…). Never group lists into blocs or attach an ideological label the
  ministry's file does not carry; if a question needs a sum of lists, say which lists, by name.
- Across a border, quote Eurostat's level honestly: unemployment, life expectancy and household
  income are NUTS 2 (Alsace, not Bas-Rhin). GDP per head is counted where it is produced — a
  commuter departement (Moselle, Haute-Savoie) looks poorer on GDP than its households are.
  Eurostat has no regional GDP or household income for Switzerland: say "not published".
