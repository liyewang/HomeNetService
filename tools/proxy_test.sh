#!/bin/bash
URL="google.com"
PROXY="socks5://127.0.0.1:1080"
RETRY=3
while [ $RETRY -gt 0 ]
do
    RESULT=`curl -so /dev/null -w "%{http_code}" $URL -x $PROXY`
    if [ "$RESULT" == "200" ] || [ "$RESULT" == "301" ]; then
        echo "Access $URL: Success [$RESULT]"
        break
    else
        echo "Access $URL: Failed [$RESULT]"
    fi
    RETRY=`expr $RETRY - 1`
    sleep 3s
done
