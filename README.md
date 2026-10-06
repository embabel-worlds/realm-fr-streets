# realm-fr-streets

France, joined at a commune — keyless official open data queryable as **one graph**
on an [Embabel](https://worlds.embabel.com) world, keyed on the INSEE commune code
(never the postal code, which is many-to-many with communes).

| Source | What | Grain |
|---|---|---|
| SSMSI, Ministère de l'Intérieur (via data.gouv.fr tabular API) | Recorded crime, 15 indicators, 2016–2025 | commune (published only above the secrecy threshold) |
| SSMSI departement base | Same, plus homicides and attempted homicides — nothing suppressed | département |
| INSEE Filosofi 2023 (Melodi API) | Median standard of living, poverty; Gini and D9/D1 by département | commune / département |
| INSEE census 2012–2023 (Melodi API) | Population, age bands, immigration status | commune / département |
| Etalab DVF statistics | Median price per m², flats and houses, last 10 half-years | commune / département |
| Répertoire national des élus | Mayors (after the March 2026 municipales), deputies | commune / département |
| geo.api.gouv.fr, API Adresse | Names, surfaces, postal codes, geocoding | commune |

No API keys and no accounts: the realm works the moment it is installed.

## Anchors

- `(:FrPlace)` — places you watch (stored).
- `(:FrCommune {code})`, `(:FrMelodiPlace {geo:'2025-COM-<code>'})`, `(:FrDeptRef {code})` — any commune or département, literal-seeded.
- `(:FrCrimeSlice {slice:'<token>|<year>|<floor>'})` — one national commune crime slice, filtered at the source.
- `(:FrDeptCrimeSlice {slice:'<token>'})` — every département, every year, for an indicator.
- `(:FrCommunes {set:'france'})`, `(:FrDepartements {set:'france'})`, `(:FrHousingScale {scale})` — whole-country covariates.

## Views

| Question | View |
|---|---|
| Everything about one commune | `FrCommuneSnapshot`, `FrCommuneContext`, `FrCommuneCrime` |
| Watched places | `FrPlaceDossier`, `FrCrimeAtMyPlaces`, `FrCrimeTrendAtPlace`, `FrDeputiesAtMyPlaces` |
| Is crime X rising in France? | `FrNationalTrend` |
| Worst départements / communes | `FrDepartementLeague`, `FrCrimeLeague` |
| Where did X rise or fall most? | `FrCrimeMovers` |
| What predicts crime across départements? | `FrDepartementModel`, `FrDepartementPredictorsOneByOne`, `FrDepartementRows` |
| What predicts crime across communes? | `FrWhatBestPredictsCrime`, `FrCrimePredictorsOneByOne`, `FrCommunesRanked`, `FrModelRows` |
| Housing against incomes | `FrHousingAffordability`, `FrDeptHousing` |

## Apps (`apps/`)

- **Portrait de ma commune** — search any commune: mayor, population and age, income and poverty, property prices and years of income for 70 m², crime against 2019, deputies, compared with its département and France.
- **Se loger en France** — "where can I buy with my budget", years of income per département, price-against-income scatter of ~3,000 towns, every commune sortable.
- **What predicts crime in France?** — switchable-predictor model across communes, refitted in the browser, with a check against the engine's own `regress()`.

Every app is bilingual: it opens in French, and an FR / EN switch at the top right changes the language (the choice is remembered in the browser). The commune portrait opens on Strasbourg. Strasbourg, like the rest of Alsace-Moselle (57, 67, 68), has no DVF property prices because sales there are recorded in the Livre foncier, and the app says so instead of showing a blank.

Apps are separate artifacts on an Embabel world (`vibe_app_save`); the HTML here is the source of each.

## Honest limits

France publishes **no geolocated crime** and nothing below the commune (bar the Paris, Lyon
and Marseille arrondissements). A commune's crime figure is published only after more than
5 facts in each of 3 consecutive years; suppressed rows are never shown as zero or replaced
by the département average. France collects **no ethnic statistics**: "immigré" (born
abroad, not French at birth) is the closest published measure, and every model treats it as
an area measure — association across places, never a statement about people. DVF excludes
Alsace-Moselle and Mayotte. Recorded crime also measures reporting and policing.

## Install

From a checkout mounted at your realms directory: `install_realm_from_path`. From git:
`install_realm` with `https://github.com/embabel-worlds/realm-fr-streets.git`.
