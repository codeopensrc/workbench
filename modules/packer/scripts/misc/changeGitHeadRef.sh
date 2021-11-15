#!/bin/bash

###! https://gitlab.com/gitlab-org/gitlab/-/issues/343905
###! Gitlab 14.4 does not restore the original HEAD correctly and will get an error on clone
# warning: remote HEAD refers to nonexistent ref, unable to checkout

###! On restore, HEAD points to refs/heads/main instead of the original
###! Below script will change the HEAD to master

###! https://stackoverflow.com/questions/11893678/warning-remote-head-refers-to-nonexistent-ref-unable-to-checkout
###! According to above link, instead of editing files this would be the 'git' way to change the HEAD
# cd path/to/bare/git/repo; git symbolic-ref HEAD refs/heads/XYZ

###! Gitlab repos at /var/opt/gitlab/git-data/repositories
###! Regular git repos under @hashed - including wiki repos (we had 2)
###! Snippet git repos under @snippets
DIR_TO_START=/var/opt/gitlab/git-data/repositories

MAX_DEPTH=5
NUM_HEADS=0

walk() {
    #dir_to_walk=$1
    #depth=$2
    #FILES=`ls $1`

    for FILE in `ls $1`; do
        #FULLPATH=$1/$FILE
        if [[ ! $1/$FILE =~ "@hashed" ]]; then continue; fi

        if [ ! -d $1/$FILE ]; then
            if [[ -f $1/$FILE && "$FILE" = "HEAD" && ! $1 =~ "wiki" ]]; then
                echo "FOUND HEAD - $1/$FILE"
                NUM_HEADS=$(( $NUM_HEADS + 1 ))
                cat $1/$FILE
                #sed -i "s/refs\/heads\/main/refs\/heads\/master/" "$1/$FILE
            fi
        fi
        if [ -d $1/$FILE ]; then
            if [ $2 -lt $MAX_DEPTH ]; then
                walk $1/$FILE $(( $2 + 1 ))
            fi
        fi
    done
}

walk $DIR_TO_START 1
echo $NUM_HEADS
