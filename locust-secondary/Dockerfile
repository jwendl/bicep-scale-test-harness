FROM locustio/locust

COPY . .

ENV MAINHOST=""

ENTRYPOINT locust -f locustfile.py --worker --master-host=$MAINHOST
