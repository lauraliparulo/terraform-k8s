spinner=(
"Working    "
"Working.   "
"Working..  "
"Working... "
"Working...."
)

max=$((SECONDS + 10))

while [[ ${SECONDS} -le ${max} ]]
do
    for item in ${spinner[*]}
    do
        echo -en "\r$item"
        sleep .1
        echo -en "\r              \r"
    done
done
