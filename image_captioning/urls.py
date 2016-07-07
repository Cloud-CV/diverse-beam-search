from django.conf.urls import url, patterns
from image_captioning import views
from django.conf import settings

urlpatterns = [
    url(r'^beam_search/$', views.beam_search, name='beam_search'),
    url(r'^char-rnn$', views.char_rnn, name='char_rnn'),
    url(r'^neuraltalk2$', views.neuraltalk2, name='neuraltalk2'),
]

urlpatterns += patterns('',
    (r'^media/(?P<path>.*)$', 'django.views.static.serve', {'document_root': settings.MEDIA_ROOT}),
)
