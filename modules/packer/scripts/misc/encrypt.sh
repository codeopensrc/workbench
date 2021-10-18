#!/bin/bash

while getopts "k:r:f:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        k) RECIPIENT_KEYFILE=$OPTARG;;
        r) RECIPIENT_FPRS=$OPTARG;;
        f) FILE=$OPTARG;;
    esac
done

### Import keys
#gpg --import $RECIPIENT_KEYFILE

### Trust keys in chain non-interactively
#gpg --export-ownertrust | sed -r "s/:.*/:5:/" | gpg --import-ownertrust

### Split string creating array of recipients
#FPR_ARR=($(echo $RECIPIENT_FPRS | tr "," "\n"))
#for FPR in "${FPR_ARR[@]}"; do
#    RECIPIENTS+=(-r $FPR)
#done


##TODO: Determine a robust way to import certain keys and specify recipients per file
## For the moment we're going to trust imported keys and allow all of them to decrypt
## This is obviously not ideal but going for MVP for the moment

FPR_ARR=( $(gpg --list-keys | sed -n -r "s/\s+([0-9A-Z]{10,})/\1/p") )
for FPR in "${FPR_ARR[@]}"; do
    RECIPIENTS+=(-r $FPR)
done

## Encrypt
#gpg --encrypt -r KEY -r KEY FILE
#gpg --encrypt --compress-algo 0 -z 0 "${RECIPIENTS[@]}" -o ${FILE}.gpg $FILE
rm ${FILE}.gpg
gpg --encrypt -z 0 "${RECIPIENTS[@]}" -o ${FILE}.gpg $FILE

