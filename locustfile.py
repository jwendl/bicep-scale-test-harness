from locust import HttpUser, task, between
import random

class MyUser(HttpUser):
    wait_time = between(1, 5)

    @task
    def index(self):
        id = random.randrange(1, 999999)
        response = self.client.get("/api/run?loyaltyId={loyaltyId}".format(loyaltyId = str(id).zfill(6)))
