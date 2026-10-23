# Belege: Was B-Guard für den Akku tun kann

Stand: 22. Oktober 2026. Diese Seite begründet, welche Funktionen B-Guard anbietet und welche entfernt wurden. Sie fasst veröffentlichte Studien und Apple-Dokumentation zusammen. Zahlen aus Laborzellen lassen sich nicht direkt auf einen bestimmten MacBook-Akku übertragen; für MacBook-Zellen selbst gibt es keine veröffentlichten Alterungsdaten.

## Was macOS selbst bietet

| Funktion | macOS | Quelle |
|---|---|---|
| Optimiertes Laden (hält bei 80 %, lernt Routine) | ab macOS 11 | [Apple 102338](https://support.apple.com/en-us/102338) |
| Ladelimit 80–100 %, Apple silicon | ab macOS Tahoe 26.4 | [Apple 102338](https://support.apple.com/en-us/102338) |
| Batteriezustand, maximale Kapazität, Nutzungsverlauf | Systemeinstellungen → Batterie | [Mac-Hilfe](https://support.apple.com/guide/mac-help/mchlfc3b7879/mac) |
| Zyklenzahl, Auslegung 1000 Zyklen bei 80 % Kapazität | Systeminformationen | [Apple 102888](https://support.apple.com/en-us/102888) |
| Betrieb bei 10–35 °C Umgebung, Lagerung etwa 50 % | – | [Apple 102336](https://support.apple.com/en-us/102336), [Apple Batterien](https://www.apple.com/batteries/maximizing-performance/) |
| Öffentliche API zum Setzen eines Ladelimits | keine | IOPowerSources.h enthält nur Lesefunktionen |

Das macOS-Ladelimit lädt bei mehr als 5 % Abfall nach und lädt gelegentlich auf 100 %, damit die Ladestandsschätzung genau bleibt.

**Mehrwert von B-Guard:** Ziele unter 80 % (nur mit SMC-Ladesperre), einstellbarer Hitzeschutz, Unterstützung für macOS 14 bis 26.3, Verlauf mit Belastungsmodell, Zeitpläne, Monitorprofil, lokale API und Kurzbefehle. Ohne Ladesperre hält macOS das Limit; B-Guard empfiehlt die passende Einstellung.

## Ladestand beim Lagern und am Netzteil

- Die Lagerungsalterung steigt nicht gleichmäßig mit dem Ladestand, sondern in Plateaus. Bei NCA-/NMC-Zellen mit Graphitanode liegt eine deutliche Stufe bei etwa 55–60 % Ladung, wenn die Anode halb lithiiert ist. ([Keil et al. 2016](https://doi.org/10.1149/2.0411609jes))
- Bei 100 % Ladung ist der Einfluss groß, unter 80 % deutlich kleiner. ([Werner et al. 2021](https://doi.org/10.3390/batteries7020028))
- Ein Akku, der am Netzteil auf konstanter Spannung gehalten wird, altert im Wesentlichen wie bei Lagerung auf diesem Ladestand. ([Azzam et al. 2025](https://doi.org/10.1002/batt.202500349))

**Folge für B-Guard:** Das Schreibtischprofil liegt jetzt bei 45–50 % statt 55–60 % und damit unterhalb der Stufe. Die Ladesperre bleibt im Schlaf aktiv, wenn der Akku im Zielbereich ist.

## Temperatur

- Die Alterung folgt einem Arrhenius-Gesetz. Der Term exp(−6976 K / T) aus [Schmalstieg et al. 2014](https://doi.org/10.1016/j.jpowsour.2014.02.012) entspricht etwa 58 kJ/mol: rund 2× schneller bei 35 °C und 4× bei 45 °C gegenüber 25 °C.
- Am günstigsten ist etwa 25 °C. Darunter gewinnen Lithium-Ablagerungen beim Laden an Bedeutung, darüber Wachstum der Grenzschicht (SEI) und Kathodenschäden. ([Waldmann et al. 2014](https://doi.org/10.1016/j.jpowsour.2014.03.112), [Kucinskis et al. 2022](https://doi.org/10.1016/j.jpowsour.2022.232129))

**Folge für B-Guard:** Hitzeschutz, ein Hinweis beim Laden unter 10 °C, ein Hinweis bei hoher Systemwärme (`ProcessInfo.thermalState`) und der temperaturgewichtete Belastungsindex im Verlauf. Hitzeschutz verhindert nur zusätzliche Ladewärme; er kühlt keinen Akku, den der Prozessor erwärmt.

## Teilzyklen und der entfernte Pendelmodus

- Flache Zyklen um einen mittleren Ladestand altern weniger als volle (40–60 % > 20–80 % > 0–100 %). ([Preger et al. 2020](https://doi.org/10.1149/1945-7111/abae37), [Gauthier et al. 2022](https://doi.org/10.1149/1945-7111/ac4b82))
- Für Pendeln zwischen 75 und 80 % gegenüber Halten bei 80 % gibt es keine direkte Studie. Die mittlere Ladung sinkt nur um etwa 2,5 Punkte und bleibt im selben Plateau, dafür kommen pro Pendel etwa 0,05 Vollzyklen hinzu.

**Folge für B-Guard:** Der Pendelmodus wurde entfernt. Ohne separate Ladesperre trennt B-Guard das Netzteil nie, um ein Limit zu halten.

## Kalibrierung

- Ein Zyklus 100 → 10 → 100 % korrigiert nur die Kapazitätsschätzung des Akkuchips, nicht den Akku. Der Chip lernt aus Spannungsmessungen in Ruhe mit mehr als 37 % Ladungsdurchsatz dazwischen. ([TI SLUA364B](https://www.ti.com/lit/pdf/slua364))

**Folge für B-Guard:** Die gesperrte Kalibrierung wurde entfernt. Eine Erinnerung nach sechs Wochen ohne Vollladung bleibt, ausdrücklich für die Genauigkeit der Anzeige.

## Grenzen und Nebenwirkungen

- Ein niedriges Limit kostet Laufzeit: 45–50 % geben rund die Hälfte der Kapazität auf.
- Nach einer Limitänderung verschiebt sich die gemessene Kapazität wochenlang vorübergehend (Anodenüberhang). ([Lewerenz et al. 2018](https://doi.org/10.1016/j.est.2018.04.029)) B-Guard weist in der Diagnose darauf hin.
- Wie viel Kapazität ein Limit im Alltag spart, ist für Laptops nicht gemessen. Eine grobe Abschätzung für einen warmen, meist angeschlossenen MacBook liegt bei einigen bis etwa 10 Prozentpunkten über zwei bis drei Jahre. Das ist eine Schätzung, kein Messwert.
- Realistische, wechselnde Last kann die Lebensdauer gegenüber Laborzyklen deutlich verlängern; Laborzahlen überschätzen den absoluten Verschleiß eher. ([Geslin et al. 2024](https://doi.org/10.1038/s41560-024-01675-8))

## Erklären statt Steuern

- Seit der Firmware von macOS 27 sind die Ladesperre-Schlüssel CHTE, CH0B und CH0C gesperrt: Sie erscheinen als Platzhalter der Größe null oder liefern selbst für root `kIOReturnNotPrivileged`. Der Netzteil-Schalter CHIE bleibt beschreibbar. B-Guard prüft deshalb die Fähigkeit und nicht die macOS-Version.
- Als Ersatz setzt B-Guard auf Wunsch das macOS-Ladelimit über die Einstellungen von PowerUIAgent (`com.apple.smartcharging.topoffprotection`, Schlüssel `mclLimitValue`). Diesen Weg haben [BatLimit](https://github.com/DmitriyODS/BatLimit) und [Battery Toolkit für macOS 27](https://github.com/andersonproescholdbell/battery-toolkit-macos27) gefunden. Er hält das Limit in der Firmware, auch im Schlaf, ohne das Netzteil umzuschalten. Den Weg über den Netzteil-Schalter nutzt B-Guard nicht, weil er nur im Wachzustand wirkt und Teilzyklen erzeugt.
- macOS lädt trotz Ladelimit gelegentlich auf 100 %, damit die Ladestandsschätzung genau bleibt. ([Apple 102338](https://support.apple.com/en-us/102338)) Steht der Akku deutlich über Ziel und Limit, nennt B-Guard das als wahrscheinliche Ursache.
- Das Energieprotokoll `pmset -g log` ist ohne Administratorrechte lesbar, sein Format aber nicht dokumentiert ([pmset(1)](https://keith.github.io/xcode-man-pages/pmset.1.html)). Unbekannte Zeilen werden übersprungen. Aktive Energie-Assertions liefert die öffentliche Funktion `IOPMCopyAssertionsByProcess` aus IOKit.
- USB-C-Kabel ohne E-Marker sind für 3 A ausgelegt und begrenzen bei 20 V auf 60 W; für bis zu 100 W oder 240 W braucht es 5-A-Kabel (USB Power Delivery). Weicht die ausgehandelte Leistung deutlich von der angebotenen ab, liegt die Grenze meist im Kabel oder Dock.
- AppleCare+ deckt einen Akkutausch, wenn der Akku weniger als 80 % seiner ursprünglichen Kapazität hält. ([Apple: Akkuservice](https://support.apple.com/mac/repair/battery)) Die Prognose nutzt die Kapazitätsquote aus Maximal- und Designkapazität, nicht Apples Anzeige „Maximale Kapazität“; Alterung verläuft nicht linear, und nach einer Limitänderung ist die Messung einige Wochen verzerrt ([Lewerenz et al. 2018](https://doi.org/10.1016/j.est.2018.04.029)).

## Weitere Quellen

- Wikner E, Thiringer T (2018). Extending Battery Lifetime by Avoiding High SOC. [doi:10.3390/app8101825](https://doi.org/10.3390/app8101825)
- Xu B et al. (2018). Modeling of Lithium-Ion Battery Degradation for Cell Life Assessment. [doi:10.1109/TSG.2016.2578950](https://doi.org/10.1109/TSG.2016.2578950)
- Wang W et al. (2024). Calendar and cycle aging of LiCoO2/graphite cells. [doi:10.1007/s11630-024-1918-z](https://doi.org/10.1007/s11630-024-1918-z)
- Apple: [Akkuzustand auf Apple silicon](https://support.apple.com/en-us/102589), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
