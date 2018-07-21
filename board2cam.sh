#!/bin/bash

# Für dieses Script benötigst Du Eagle, pcb2gcode und Fritzing. Du findest diese 
# Programme hier:
#
#   Eagle:	http://www.cadsoft.de/
#   pcb2gcode:	http://sourceforge.net/apps/mediawiki/pcb2gcode
#   Fritzing:	http://fritzing.org/
#   zenity
#
# Stefan May <smay@4finger.net>  und andere Leute, die auch noch reingepfuscht haben
# Lizenz: CC-BY-SA http://creativecommons.org/licenses/by-sa/2.0/

# --debug: temporäre Dateien nicht löschen

cd ~/Desktop/;

# Dialog: Datei auswählen
importfile=$(zenity --title="Zu konvertierende Datei auswählen" --file-selection --file-filter="Alle unterstützten | *.brd *.fzz" --file-filter="EAGLE board file (*.brd) | *.brd" --file-filter="Fritzing-Paket (*.fzz) | .fzz");

# ausgewählte Datei muss existieren
if [ -f "$importfile" ] ; then

	# Möglicherweise existiert der Ordner schon
	if [ -d "$importfile-files" ]; then
		echo "Der Ordner '$importfile-files' existiert bereits!";
		zenity --question --text="Der Ordner\n'$importfile-files'\nexistiert bereits!\nOrdner löschen?" --title="Fehler!" --ok-label="Ja" --cancel-label="Nein";
		if [ $? == 0 ]; then
			rm -rf "$importfile-files";
		else
			echo "Abbruch.";
			zenity --error --text="Abbruch." --title="Abbruch"
			exit 1;
		fi
	fi

	mkdir "$importfile-files"			# Ordner anlegen
	cd "$importfile-files/"				# in den Ordner wechseln
	cp "$importfile" "$importfile-files/pcb"	# Kopie der Eingabedatei reinwerfen


	# Konfigurationsdatei für pcb2gcode anlegen
	cat >millproject <<EOF
# everything in here is in millimeter
metric=1
# high offset means voronoi regions will be calculated
EOF

	# offset einlesen (Leiterbahnen auflbasen)
	offset=$(zenity --scale --title="Leiterbahnen aufblasen" --text="Wie viel mm sollen die Leiterbahnen aufgeblasen werden?\n\nTypische Werte:\n\tSMD: 5 (0.5 mm)\n\tNormal: 23 (2.3 mm)" --value=23 --min-value=0 --max-value=200)
	offset=$(echo - | awk "{ print $offset/10}")
	echo "offset=$offset" >> millproject; # und in die config schreiben

	# Milldrill einschalten? (Löcher in der richtigen Größe fräsen)
	echo "Sollen die Löcher in der richtigen Größe gefräst werden? (milldrill einschalten)";
	zenity --question --text="Sollen die Löcher in der richtigen Größe gefräst werden?\n(milldrill einschalten)" --title="milldrill einschalten?" --ok-label="Ja" --cancel-label="Nein";
	if [ $? == 0 ]; then
		echo "milldrill=1" >> millproject; # Milldrill an
		zenity --warning --text="Achtung! Die Löcher werden gefräst! Keine Bohrer, sondern Fräser zum Fräsen der Löcher verwenden!" --title="Warnung (milldrill an)";
	fi

	# Rest der Konfigurationsdatei
	cat >>millproject <<EOF
dpi=1000

# parameters for isolation routing / engraving / etching
zwork=-2.9
zsafe=5
zchange=30
mill-feed=1100
mill-speed=20000

# parameters for cutting out boards
cutter-diameter=0.8
zcut=-3
cut-feed=200
cut-speed=20000
cut-infeed=0.1
outline-width=0.3
fill-outline=1

# drilling parameters
zdrill=-3
drill-feed=100
drill-speed=20000

EOF



	# Um was für eine Datei handelt es sich denn überhaupt?

	if [ ${importfile##*\.} == "brd" ]; then	# EAGLE-Datei *.brd

		mv ./pcb ./pcb.brd

		# EAGLE board Datei zu Gerber
		echo "EAGLE board file wird zu Gerber-Dateien konvertiert..."
		(
		echo 0;
		~/eagle/bin/eagle -X -O+ -dGERBER_RS274X	-oback.cnc	pcb.brd Bot Pads Vias >&2;
		echo 16;
		~/eagle/bin/eagle -X -O+ -dGERBER_RS274X	-ofront.cnc	pcb.brd Top Pads Vias >&2;
		echo 33;
		~/eagle/bin/eagle -X -O+ -dEXCELLON		-odrill.cnc	pcb.brd Drills Holes >&2;
		echo 50;
		~/eagle/bin/eagle -X -O+ -dGERBER_RS274X	-ooutline.cnc	pcb.brd Dimension >&2;
		echo 66;
		~/eagle/bin/eagle -X -O+ -dPS		-oback_stop.ps	pcb.brd bStop Dimension >&2;
		echo 83;
		~/eagle/bin/eagle -X -O+ -dPS		-ofront_stop.ps	pcb.brd tStop Dimension >&2;
		echo 100;
		) | zenity --progress --title="[EAGLE] Konvertiere..." --text="Aus EAGLE-Board-Dateien werden Gerber-Dateien generiert..." --auto-close;


		# Gerber zu G-Code
		echo "Gerber-Dateien werden zu G-Code konvertiert..."
		(
		echo 10;
		pcb2gcode --outline outline.cnc --back back.cnc --front front.cnc --drill drill.cnc >&2;
		echo 100;
		) | zenity --progress --title="[pcb2gcode] Konvertiere..." --text="Aus Gerber-Dateien wird G-Code generiert..." --pulsate --auto-close;

		if [ "$1" != "--debug" ]; then
			echo "Aufräumen..."
			# remove temporary files
			rm -f pcb.brd
			rm -f back.cnc back.gpi
			rm -f front.cnc front.gpi
			rm -f outline.cnc outline.gpi
			rm -f drill.cnc drill.dri
			#rm -f *.png
			#rm -f  millproject
		fi

		echo "Fertig."
		zenity --question --text="Fertig. Beinhaltenden Ordner öffnen?" --title="Fertig." --ok-label="Ja" --cancel-label="Nein";
		if [ $? == 0 ]; then
			nautilus "$importfile-files" &
		fi

	elif [ ${importfile##*\.} == "fzz" ]; then	# Fritzing-Paket *.fzz

		# Fritzing-Paket auspacken (darin befindet sich eine .fz-Datei)
		# (muss ausgepackt werden, damit Fritzing das beim Start nicht macht und nachfrägt)
		unzip ./pcb

		name=$(ls ./*.fz);
		name="${name%\.*}";

		# Fritzing-Paket richtig umbenennen
		mv ./pcb "./$name.fzz"

		# Fritzing-Paket in Gerber umwandeln
		echo "Fritzing-Paket wird zu Gerber-Dateien konvertiert..."
		(
		echo 10; # Damit die Progressbar pulsiert
		/home/cnc/fritzing-0.8.3b.linux.i386/Fritzing.sh -gerber "$PWD/" "./$name.fz" >&2; # Ich schreibe das dreckigerweise mal auf STDERR, damit das im Terminal und nicht im Zenity landet
		echo 100; # Damit Zenity schließt
		) | zenity --progress --title="[Fritzing] Konvertiere..." --text="Aus dem Fritzing-Paket werden Gerber-Dateien generiert..." --pulsate --auto-close;

		# Gerber in G-Code umwandeln
		echo "\nGerber-Dateien werden zu G-Code konvertiert..."
		(
		echo 10;
		pcb2gcode --outline $name"_contour.gm1" --back $name"_copperBottom.gbl" --front $name"_copperTop.gtl" --drill $name"_drill.txt" >&2;
		echo 100;
		) | zenity --progress --title="[pcb2gcode] Konvertiere..." --text="Aus den Gerber-Dateien wird G-Code generiert..." --pulsate --auto-close;


		# Fehler im Drill-File beseitigen
		echo "Überprüfe den Bohr-G-Code in './drill.ngc.ngc' auf Kreisfahrten mit zu kleinem Durchmesser..."
		(
		$(dirname "$0")/drilloptimizer.sh ./drill.ngc.ngc;
		) | zenity --progress --title="Überprüfe..." --text="Überprüfe den Bohr-G-Code auf Kreisfahrten mit zu kleinem Durchmesser..." --percentage=0 --auto-close;

		if [ "$1" != "--debug" ]; then
			# Aufräumen
			echo "Aufräumen..."
			rm -f "$name"*;
			rm -f ./millproject
			#rm -f *.png
		fi

		echo "Fertig."
		zenity --question --text="Fertig. Beinhaltenden Ordner öffnen?" --title="Fertig." --ok-label="Ja" --cancel-label="Nein";
		if [ $? == 0 ]; then
			nautilus "$importfile-files" &
		fi

	else
		echo "Bitte eine EAGLE-Board-Datei (*.brd) oder Fritzing-Paket (*.fzz) auswählen.";
		zenity --error --text="Bitte eine EAGLE-Board-Datei (*.brd) oder Fritzing-Paket (*.fzz) auswählen." --title="Fehler"
	fi
else
	echo "Die angegebene Datei existiert nicht. Abbruch.";
	zenity --error --text="Die angegebene Datei existiert nicht. Abbruch." --title="Fehler"
fi

