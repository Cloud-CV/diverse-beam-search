from django.conf.urls import url
from image_captioning import views

urlpatterns = [
    url(r'^beam_search/$', views.beam_search, name='beam_search'),
    url(r'^$', views.home, name='home'),
]
