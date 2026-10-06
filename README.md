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
| INSEE census 2023 (Melodi API) | Unemployment (census, self-declared), highest qualification | commune |
| Ministère de l'Intérieur, European elections 9 June 2024 | Final results, every one of the 38 lists, by panel number | commune |
| Eurostat regional statistics, GISCO NUTS 2024 | GDP and household income per head (PPS), unemployment, youth unemployment, life expectancy, median age, population, density, since 2012 | NUTS 3 / NUTS 2 / country, all of Europe |

No API keys and no accounts: the realm works the moment it is installed.

## Anchors

- `(:FrPlace)` — places you watch (stored).
- `(:FrCommune {code})`, `(:FrMelodiPlace {geo:'2025-COM-<code>'})`, `(:FrDeptRef {code})` — any commune or département, literal-seeded.
- `(:FrCrimeSlice {slice:'<token>|<year>|<floor>'})` — one national commune crime slice, filtered at the source.
- `(:FrDeptCrimeSlice {slice:'<token>'})` — every département, every year, for an indicator.
- `(:FrCommunes {set:'france'})`, `(:FrDepartements {set:'france'})`, `(:FrHousingScale {scale})` — whole-country covariates.
- `(:EuRegion {code})` — any European NUTS region (Bas-Rhin `FRF11`, Ortenaukreis `DE134`, Basel-Stadt `CH031`, Alsace `FRF1`, Germany `DE`).

The `{set:'france'}` anchors and the collect/`UNWIND` regrouping in the national views are workarounds for engine gaps, tracked in
[embabel/me#2344](https://github.com/embabel/me/issues/2344); they go when it lands.

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
| France against its neighbours, border by border | `EuBorderRegions` |

The census work and qualification tables (`FrWork`, `FrEducation`) and the European 2024 results (`FrEuroVote`) are queryable per commune and per
watched place now. National views over them — a vote model with switchable predictors, unemployment and qualifications in the crime model — wait on
[embabel/me#2347](https://github.com/embabel/me/issues/2347) rather than adding to the regroup workaround. The realm never groups lists into blocs or
labels them: each list is reported by its panel number and the ministry's own title and nuance code.

## Apps (`apps/`)

- **Portrait de ma commune** — search any commune: mayor, population and age, income and poverty, property prices and years of income for 70 m², crime against 2019, deputies, compared with its département and France.
- **Se loger en France** — "where can I buy with my budget", years of income per département, price-against-income scatter of ~3,000 towns, every commune sortable.
- **What predicts crime in France?** — switchable-predictor model across communes, refitted in the browser, with a check against the engine's own `regress()`.
- **De l'autre côté de la frontière** — France against its neighbours on one European yardstick: pick a border (Rhine, Lorraine–Saar–Luxembourg, Nord, Ardennes, Jura, Léman, Alps, Pyrenees) and an indicator; regions on both sides, their NUTS 2 regions and the countries, latest values and trends since 2012.

Every app is bilingual: it opens in French, and an FR / EN switch at the top right changes the language (the choice is remembered in the browser). The commune portrait opens on Strasbourg, and the cross-border app on the Rhine at Strasbourg. Strasbourg, like the rest of Alsace-Moselle (57, 67, 68), has no DVF property prices because sales there are recorded in the Livre foncier, and the app says so instead of showing a blank.

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
