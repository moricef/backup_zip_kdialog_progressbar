#!/usr/bin/bash
# $Id: backup_zip_kdialog_progressbar v 1.10 2024/07/18 fab2 $

# Prérequis : environnement KDE pour kdialog

# Définitions des flux :
# Entrée standard stdin 0
# Sortie standard stdout 1
# Erreur standard stderr 2

# Variable DATE au format jour/mois/année/heure/minutes
DATE=`date +%d%m%y%H%M`

# variable CLIENTNAME initialisée vide
CLIENTNAME=

# Expression régulière définissant un motif de caractères A à Z en majuscules, compris entre le début ^ et la fin de ligne $
REGEXP=^[[:upper:]]+$

# La sortie de la saisie du nom client via kdialog est envoyée à la boucle principale while qui lit la ligne. Si correspond à REGEXP, alors écrit la ligne dans variable CLIENTNAME.
# Sinon boucle secondaire until qui tourne tant que la saisie ne correspond pas à REGEXP, affiche une boite de message kdialog  à fermer par clic sur OK puis ouvre
# une nouvelle boîte de saisie qui envoie la saisie dans la boucle tertiaire while read line controlée par la boucle until. Si until renvoie vrai, sortie de la boucle until secondaire 
# et de la boucle while tertiaire par break, puis enregistrement de la ligne saisie dans CLIENTNAME.

##
# Il ya peut être une méthode plus simple ... ;-)
##

while read line; do

    if [[ "${line}" =~ ${REGEXP} ]]; then
        CLIENTNAME=$line
    else
        until [[ "${line}" =~ ${REGEXP} ]]; do
            kdialog --sorry "Saisie du nom du client incorrecte !"
            while read line; do
                break
            done < <(kdialog --title "Nom Client" --inputbox "Veuillez saisir à nouveau le nom du client en respectant :\n 1 Mot uniquement, en MAJUSCULE, pas de caractères spéciaux, ni espace, ...")
        done
        CLIENTNAME=$line
    fi
done < <(kdialog --title "Nom Client" --inputbox "Saisir le nom du client (En MAJUSCULE , 1 Mot uniquement, pas de caractères spéciaux, espace, ...)")
echo $CLIENTNAME


# Le mot de passe pour ouvrir l'achive zip cryptée est composé du nom du client + EO@09 et enregistré dans la variable PASSWORD.
PASSWORD=$CLIENTNAME"EO@09"

# Boîte kdialog cliquable demandant le chemin du répertoire source à sauvergarder. Enregistrement de la saisie dans la variable INPATH.
INPATH=`kdialog --title "Sélectionnez le répertoire source à sauvegarder" --getexistingdirectory /media/`

# Boîte kdialog demandant le chemin du répertoire cible où enregistrer l'archive zip et  enregistrement de la saisie dans la variable OUTPATH.
OUTPATH=`kdialog --title "Sélectionnez le répertoire cible (destination)" --getexistingdirectory /media/`

OUTPATHFILE=$CLIENTNAME$DATE".zip"

# tee lit l'entrée standard et la redirige sur la sortie standard et en même temps dans 1 fichier. Redirection de stdout vers tee par substitution de  processus
# (la sortie de la commande zip (stdout) devient l'entrée de tee), puis de  stderr via stdout. tee envoie stdout (et stderr) à la fois dans le fichier
# nomclient_backup_date.log dans le répertoire du script et l'affiche sur le terminal.
exec 1> >( tee ./$CLIENTNAME"_backup_"$DATE".log" ) 2>&1

# Se place dans le répertoire cible
cd $OUTPATH

# ls liste récursivement les fichiers du répertoire source et les affiche un par ligne. awk affiche les lignes sauf celles qui sont vides et celles, 
# correspondant aux répertoires, se terminant par le caractère ":"  et wc -l donne le nombre de lignes <==> le nombre de fichiers.
NOMBREFICHIERS=`ls -R -1 $INPATH/* |awk '!/^[[:space:]]*$/ && !/[:]+$/'|wc -l`
echo $NOMBREFICHIERS

# formatage du message "ANNULATION PAR L'UTILISATEUR".
ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"

# Initialisation de count à 1
count=1

# definition de a, type de boîte de dialogue avec barre de progression maxi 100 :
a=$(kdialog --title $"Sauvegarde zip" --progressbar $"Progression de la sauvegarde ..." 100);

# Pause de 2 secondes.
sleep 2;

# Affichage du bouton d'annulation
qdbus $a showCancelButton true

# boucle while pour read qui lit en entrée les lignes envoyées par la sortie de zip, reçues une à une.
# boucle while imbriquée quand le bouton annulation est activé pour fermer la boite kdialog, afficher le message "ANNULATION PAR L'UTILISATEUR" 
# si le script est lancé dans un terminal, puis sortie du script.
while read line
do
    qdbus $a org.kde.kdialog.ProgressDialog.setLabelText $"Processing file..... $line"
        while [[ $(qdbus $a wasCancelled) != "false" ]]
        do
            echo -e "$COL_RED ANNULATION PAR L'UTILISATEUR $COL_RESET"
            qdbus $a org.kde.kdialog.ProgressDialog.close
            exit
        done
# la variable $v utilisée comme valeur par la barre de progression. Première ligne de la sortie de zip v=1*100/NOMBREFICHIERS 
# (ex si $NOMBREFICHIERS=105  v=1*100/105 = 0,9533 == 0,9533%) puis $count est incrémenté de +1 à chaque tour dans la boucle. Deuxième ligne de la sortie
# de zip v = 2*100/105 = 1,905 == 1,905%) jusqu'à v = 105*100/105 = 100 soit 100%.
    v=$(($(($count*100))/$NOMBREFICHIERS ))
    echo $(($count*100)) and
    count=$(($count+1))
    echo "qdbus $a Set org.kde.kdialog.ProgressDialog value $v"
    qdbus $a Set org.kde.kdialog.ProgressDialog value $v
        
done< <( zip -v -r -e -P $PASSWORD $OUTPATHFILE $INPATH ) # La sortie de zip est envoyée dans la boucle while principale. Options -v verbose, -r recursif, taux de compression par défaut = 6,
# -e archive encryptée, -P mot de passe puis nom archive, chemin du répertoire source à sauvegarder. J'ai retiré l'option -j junk-path car cette option empêche le fonctionnement de la boucle et
# lors de la décompression de l'archive, les fichiers se retrouveraient orphelins de leur chemin.

# Fermeture de la boîte kdialog à la fin du processus.
qdbus $a  org.kde.kdialog.ProgressDialog.close
