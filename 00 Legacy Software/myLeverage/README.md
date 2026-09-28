# Legacy Simulation Package myLeverage

Dieser Ordner enthält eine frühe Alpha-Version des Packages myLeverage, das zur Umsetzung und Veranschaulichung von Backtest-Simulationen für gehebelte Anlagestrategien dient.

Der hier bereitgestellte Code ist ausdrücklich nicht als produktives, validiertes oder methodisch konsistentes Analysewerkzeug zu verstehen. Es handelt sich um eine alte, experimentelle Version, um die generelle Funktionsweise bestimmter Backtest- und Simulationsabläufe nachvollziehbar zu machen. In einzelnen Bereichen des Codes sind Aktualisierungen der Alpha-Version erfolgt, um diese Nachvollziehbarkeit zu untersützten, ein dezidierte Korrektur systemischer oder struktureller Probleme erfolgte nicht. Entsprechend enthält diese Software erhebliche methodische Inkonsistenzen, analytische Ungenauigkeiten sowie steuerliche, transaktionsbezogene und rechtliche Vereinfachungen bzw. Fehler.

Insbesondere können unter anderem folgende Punkte betroffen sein:

- Modellierung von Transaktionskosten
- steuerliche Behandlung von Kapitalerträgen, Verlusten und Umschichtungen
- Rebalancing-Logik
- Behandlung von Hebelprodukten und Finanzierungskosten
- Annahmen zu Liquidität, Slippage und Ausführungspreisen
- Datenaufbereitung und Datenqualität
- Performance-, Risiko- und Drawdown-Berechnungen
- methodische Konsistenz zwischen verschiedenen Simulationsmodulen

Sofern Analysen und Ergebnisse auf Basis dieser Software erzeugt werden, sollten sie unter keinen Umständen als belastbare Finanzanalyse, Anlageempfehlung oder reproduzierbare Grundlage für Anlageentscheidungen verstanden werden.

## Abgrenzung zum Inhalt der Projekt-Codes

Diese Alpha-Version ist nicht identisch mit der Version des Packages, die für die Berechnungen und Ergebnisse in den anderen Projektordnern dieses Repositories verwendet wurde. Sie wird hier ausschließlich zu Orientierungs-, Dokumentations- und Veranschaulichungszwecken bereitgestellt. Die Veröffentlichung soll helfen, den grundsätzlichen Aufbau und die Arbeitsweise früher Backtest-Simulationen nachvollziehbar zu machen, nicht jedoch eine vollständige oder korrekte Reproduktion der veröffentlichten Analysen ermöglichen. Das Package wird weder weiterentwickelt noch gepflegt.

## Nutzung auf eigene Verantwortung

Die Nutzung des Codes erfolgt ausschließlich auf eigene Verantwortung. Es wird keine Gewähr übernommen für:

- Korrektheit
- Vollständigkeit
- methodische Konsistenz
- steuerliche oder rechtliche Richtigkeit
- Eignung für bestimmte Analysezwecke
- Reproduzierbarkeit konkreter Ergebnisse
- Kompatibilität mit aktuellen Datenquellen oder Softwareversionen

Der Code sollte nicht für reale Anlageentscheidungen, steuerliche Bewertungen, rechtliche Einschätzungen oder produktive Analysen verwendet werden.