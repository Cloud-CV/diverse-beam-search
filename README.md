
# Diverse Beam Search

[![Join the chat at https://gitter.im/Cloud-CV/Lobby](https://badges.gitter.im/Cloud-CV/Lobby.svg)](https://gitter.im/Cloud-CV/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Beam search, the standard work-horse for decoding outputs from neural sequence models like RNNs produces generic and uninteresting sequences. This is inadequate for AI tasks with inherent ambiguity — for example, there can be multiple correct ways of describing the contents of an image. To overcome this we propose a diversity-promoting replacement, Diverse Beam Search that produces sequences that are significantly different — with runtime and memory requirements comparable to beam search.

**Diverse Beam Search Demo**: http://dbs.cloudcv.org/captioning

[Imgur](http://i.imgur.com/SDsw7sP.gif)

## Installing / Getting started

We use RabbitMQ to queue the submitted jobs. Also, we use Redis as backend for realtime communication using websockets.

All the instructions for setting Grad-CAM from scratch can be found  [here](https://github.com/Cloud-CV/diverse-beam-search/blob/master/INSTALLATION.md)

Note: For best results, its recommended to run the Grad-CAM demo on GPU enabled machines.

## Interested in Contributing?

Cloud-CV always welcomes new contributors to learn the new cutting edge technologies. If you'd like to contribute, please fork the repository and use a feature branch. Pull requests are warmly welcome.

If you have more questions about the project, then you can talk to us on our [Gitter Channel](https://gitter.im/Cloud-CV/Lobby).  

## Acknowledgements

- [Original Diverse Beam Search Code](https://github.com/ashwinkalyan/dbs)
- [NeuralTalk2](https://github.com/karpathy/neuraltalk2/)
- [PyTorch](https://github.com/hughperkins/pytorch)
