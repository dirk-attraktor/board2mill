#!/bin/bash

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cd ~/Desktop/

export EAGLEEXE="/opt/eagle-9.6.2/eagle"  # dont name this EAGLE, or eagle breaks
export FRITZING="/usr/bin/Fritzing"
export PCB2GCODE="/usr/local/bin/pcb2gcode"

export PARAMETERS="

## ENGRAVING ##
zsafe=5			# (mm)     Z-coordinate for movements between engraving steps
mill-feed=1100	 	# (mm/min) Feedrate at which engraving takes place (horizontal speed)
mill-speed=20000 	# (rpm)    Spindle speed during engraving
mill-diameters=0.1       # (mm)     Diameters of mill bits, used in the order that they are provided.  

## DRILLING ##
zchange=10		# (mm)     Z-coordinate for movements with the drill head
drill-feed=100		# (mm/min) Feed rate for drilling (vertical speed)
drill-speed=20000	# (rpm)    Spindle speed during drilling (rounds per minute)

## OUTLINE ##
cut-feed=200		# (mm/min) Feedrate at which outline cutting takes place (horizontal speed)
cut-speed=20000		# (rpm)    Spindle speed during outline cutting 
fill-outline=1		# (bool)   Assume that the outline file contains not a polygon but a closed chain of lines. The board will be cut along the centres of these lines.
bridges=2		# (mm)     Add bridges with the given width to the outline cut.  --bridgesnum bridges will be created for each outline closed line.

## OTHER ##
metric=1		# (bool)   Use metric units for parameters. Does not affect output code
metricoutput=1		# (bool)   Use metric units for output code
zero-start=1		# (bool)   Set the starting point of the project at (0,0). With this option, the projet will be between (0,0) and (max_x_value, max_y_value) (positive values)
mirror-absolute=1	# (bool)   Mirror operations on the back side along the Y axis instead of the board center, which is the default

"


if [ "$1" == "--debug" ]; then
	set -x
fi

# Dialog: Datei auswählen
importfile=$(zenity --title="Zu konvertierende Datei auswählen" --file-selection --file-filter="Alle unterstützten | *.brd *.fzz *.kicad_pcb" --file-filter="EAGLEEXE board file (*.brd) | *.brd" --file-filter="Fritzing-Paket (*.fzz) | .fzz" --file-filter="KiCAD board file (*.kicad_pcb) | *.kicad_pcb");


# ausgewählte Datei muss existieren
if [ -f "$importfile" ] ; then

	# Möglicherweise existiert der Ordner schon
	if [ -d "$importfile-files" ]; then
		echo "Der Ordner '$importfile-files' existiert bereits!";
		zenity --width 800 --question --text="Der Ordner\n'$importfile-files'\nexistiert bereits!\nOrdner löschen?" --title="Fehler!" --ok-label="Ja" --cancel-label="Nein";
		if [ $? == 0 ]; then
			rm -rf "$importfile-files";
		else
			echo "Abbruch.";
			zenity  --width 800 --error --text="Abbruch." --title="Abbruch"
			exit 1;
		fi
	fi

	# Output Folder anlegen
	mkdir "$importfile-files"			# Ordner anlegen
	cd "$importfile-files/"				# in den Ordner wechseln
	cp "$importfile" "$importfile-files/pcb"	# Kopie der Eingabedatei reinwerfen

	echo "$PARAMETERS" > millproject
	

	# Seite auswählen
	selected_side=$(zenity  --width 800 --height 400 --list   --title="Seite auswählen" --text "Platinenseite auswählen" --column="Seite"  --column="Beschreibung" "Front" "Nur Vorderseite herstellen" "Back" "Nur Rückseite herstellen" "Beidseitig" "Reihenfolge beachten: Front, Back, Drill, Outline")
	side="back"	
	if [ $selected_side == "Front" ]; then
		side="front"
	fi
	echo "cut-side=$side"   >> millproject; 
	echo "drill-side=$side" >> millproject; 


	# Platinen dicke
	pcb_thickness=$(zenity --scale --title="Platinen Dicke" --text="Platinen Dicke:\nTypischer Wert: 16 (1.6 mm)\n" --value=16 --min-value=2 --max-value=40)
	zdrill=$(echo - | awk "{ print $pcb_thickness/10}" | sed s/","/"."/g)
	zcut=$(echo - | awk "{ print $pcb_thickness/10}" | sed s/","/"."/g)
	echo "zdrill=-$zdrill" >> millproject; 
	echo "zcut=-$zcut"     >> millproject; 

	# offset einlesen (Leiterbahnen aufblasen)
	offset=$(zenity --scale --title="Leiterbahnen aufblasen" --text="Wie viel mm sollen die Leiterbahnen aufgeblasen werden?\nTypischer Werte:\n\tSMD: 5 (0.5 mm)\n\tNormal: 23 (2.3 mm)" --value=23 --min-value=0 --max-value=200)
	offset=$(echo - | awk "{ print $offset/10}" | sed s/","/"."/g)
	echo "offset=$offset" >> millproject; 

	# Milldrill einschalten?
	zenity --width 600 --question --text="Löcher fräsen oder bohren? \n" --title="Milldrill einschalten?" --ok-label="Fräsen" --cancel-label="Bohren";
	if [ $? == 0 ]; then
		echo "milldrill=1" >> millproject; # Milldrill an
		md_diameter=$(zenity --scale --title="Fräser Durchmesser" --text="Durchmesser des Loch Fräsers?\nTypischer Wert: 8 (0.8 mm)\n" --value=8 --min-value=4 --max-value=20)
		md_diameter=$(echo - | awk "{ print $md_diameter/10}" | sed s/","/"."/g)	
		echo "milldrill-diameter=$md_diameter" >> millproject;
	fi

	# Gravurtiefe
	zwork=$(zenity --scale --title="Gravur Tiefe" --text="Gravurtiefe einstellen.\nTypischer Wert: 10 (0.10 mm) Max: 100 (1.00mm)" --value=10 --min-value=1 --max-value=100)
	zwork=$(echo - | awk "{ print $zwork/100}" | sed s/","/"."/g)
	echo "zwork=-$zwork" >> millproject; 

	# Durchmesser zum outline Fräsen
	cutter_diameter=$(zenity --scale --title="Ausfräser Durchmesser" --text="Durchmesser des Outline Fräsers.\nTypischer Wert: 20 (2 mm)" --value=20 --min-value=10 --max-value=40)
	cutter_diameter=$(echo - | awk "{ print $cutter_diameter/10}" | sed s/","/"."/g)
	cutter_infeed=$(echo - | awk "{ print $cutter_diameter/2}" | sed s/","/"."/g)
	echo "cutter-diameter=$cutter_diameter" >> millproject
	echo "cut-infeed=$cutter_infeed"        >> millproject; 

	# Anzahl brücken 
	bridgesnum=$(zenity --scale --title="Brücken Anzahl" --text="Haltestege in Outline einfügen. Anzahl:" --value=0 --min-value=0 --max-value=10)
	zbridges=$(echo - | awk "{ print $zcut/2 }" | sed s/","/"."/g)
	echo "bridgesnum=$bridgesnum" >> millproject; 
	echo "zbridges=-$zbridges"    >> millproject; 


	# Um was für eine Datei handelt es sich denn überhaupt?
	if [ ${importfile##*\.} == "brd" ]; then	# EAGLEEXE-Datei *.brd

		mv ./pcb ./pcb.brd
		
		# EAGLEEXE board Datei zu Gerber
		echo "EAGLEEXE board file wird zu Gerber-Dateien konvertiert..."
		(
		echo 0;
		$EAGLEEXE -X -O+ -dGERBER_RS274X -oback.cnc       pcb.brd Bot Pads Vias >&2;
		echo 16;
		$EAGLEEXE -X -O+ -dGERBER_RS274X -ofront.cnc      pcb.brd Top Pads Vias >&2;
		echo 33;
		$EAGLEEXE -X -O+ -dEXCELLON      -odrill.cnc      pcb.brd Drills Holes >&2;
		echo 50;
		$EAGLEEXE -X -O+ -dGERBER_RS274X -ooutline.cnc    pcb.brd Dimension >&2;
		echo 66;
		$EAGLEEXE -X -O+ -dPS            -oback_stop.ps   pcb.brd bStop Dimension >&2;
		echo 83;
		$EAGLEEXE -X -O+ -dPS            -ofront_stop.ps  pcb.brd tStop Dimension >&2;
		echo 100;
		) | zenity   --progress --title="[EAGLEEXE] Konvertiere..." --text="Aus EAGLEEXE-Board-Dateien werden Gerber-Dateien generiert..." --auto-close;


		# Gerber zu G-Code
		echo "Gerber-Dateien werden zu G-Code konvertiert..."
		(
		echo 10;
		$PCB2GCODE --outline outline.cnc >&2;
		$PCB2GCODE --back    back.cnc  --front   front.cnc  --drill   drill.cnc      >&2;
	
		echo 100;
		) | zenity   --progress --title="[pcb2gcode] Konvertiere..." --text="Aus Gerber-Dateien wird G-Code generiert..." --pulsate --auto-close;


	elif [ ${importfile##*\.} == "fzz" ]; then	# Fritzing-Paket *.fzz
		unzip ./pcb
5
		name=$(ls ./*.fz);
		name="${name%\.*}";
		mv ./pcb "./pcb.fzz"
		mv ./$name.fz "./pcb.fz"

		# Fritzing-Paket in Gerber umwandeln
		echo "Fritzing-Paket wird zu Gerber-Dateien konvertiert..."
		(
		echo 10; # Damit die Progressbar pulsiert
		$FRITZING -gerber "$PWD/" "./pcb.fz" >&2; # Ich schreibe das dreckigerweise mal auf STDERR, damit das im Terminal und nicht im Zenity landet
		echo 100; # Damit Zenity schließt
		) | zenity --progress --title="[Fritzing] Konvertiere..." --text="Aus dem Fritzing-Paket werden Gerber-Dateien generiert..." --pulsate --auto-close;

		# Gerber in G-Code umwandeln
		echo "\nGerber-Dateien werden zu G-Code konvertiert..."
		(
		echo 10;
		$PCB2GCODE --outline "pcb_contour.gm1"      >&2;
		$PCB2GCODE --back    "pcb_copperBottom.gbl" >&2;
		$PCB2GCODE --front   "pcb_copperTop.gtl"    >&2;
		$PCB2GCODE --drill   "pcb_drill.txt"        >&2;
		
		
		echo 100;
		) | zenity --progress --title="[pcb2gcode] Konvertiere..." --text="Aus den Gerber-Dateien wird G-Code generiert..." --pulsate --auto-close;


	elif [ ${importfile##*\.} == "kicad_pcb" ]; then	# KiCAD *.kicad_pcb
		mv ./pcb "./pcb.kicad_pcb"
		
		echo "KiCAD-Paket wird zu Gerber-Dateien konvertiert..."
		(
		echo 10; # Damit die Progressbar pulsiert
		python "$SCRIPTPATH/kicad2gerber.py" pcb.kicad_pcb  >&2; # Ich schreibe das dreckigerweise mal auf STDERR, damit das im Terminal und nicht im Zenity landet
		echo 100; # Damit Zenity schließt
		) | zenity --progress --title="[Fritzing] Konvertiere..." --text="Aus dem kicad-Paket werden Gerber-Dateien generiert..." --pulsate --auto-close;

		# Gerber in G-Code umwandeln
		echo "\nGerber-Dateien werden zu G-Code konvertiert..."
		(
		echo 10;
		$PCB2GCODE --outline "pcb.gml";
		$PCB2GCODE --back    "pcb.gbl";
		$PCB2GCODE --front   "pcb.gtl";
		$PCB2GCODE --drill   "pcb.txt";
		
		echo 100;
		) | zenity  --progress --title="[pcb2gcode] Konvertiere..." --text="Aus den Gerber-Dateien wird G-Code generiert..." --pulsate --auto-close;


	else
		echo "Bitte eine EAGLEEXE-Board-Datei (*.brd) oder Fritzing-Paket (*.fzz) auswählen.";
		zenity  --width 600 --error --text="Bitte eine EAGLEEXE-Board-Datei (*.brd) oder Fritzing-Paket (*.fzz) auswählen." --title="Fehler"
		exit 1
	fi

	if [ "$1" != "--debug" ]; then
		rm -f pcb.* *.cnc *.gpi *.png *.svg *.zip *.fzp *.ino pcb_*.* millproject
	fi

	mv back.ngc       back.gcode
	mv front.ngc      front.gcode
	mv outline.ngc    outline.gcode
	mv milldrill.ngc  milldrill.gcode
	mv drill.ngc      drill.gcode

	zenity  --width 600  --question --text="Fertig. Beinhaltenden Ordner öffnen?" --title="Fertig." --ok-label="Ja" --cancel-label="Nein";
	if [ $? == 0 ]; then
		nautilus "$importfile-files" &
	fi

else
	echo "Die angegebene Datei existiert nicht. Abbruch.";
	zenity  --width 600  --error --text="Die angegebene Datei existiert nicht. Abbruch." --title="Fehler"
fi

