from django.conf.urls import url
from image_captioning import views
from django.conf import settings

urlpatterns = [
    url(r'^beam_search/$', views.beam_search, name='beam_search'),
    url(r'^$', views.home, name='home'),
]

if settings.DEBUG:
    # static files (images, css, javascript, etc.)
    urlpatterns += patterns('',
        (r'^media/(?P<path>.*)$', 'django.views.static.serve', {
        'document_root': settings.MEDIA_ROOT}))
