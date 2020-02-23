# ingress installer


## run

```bash
docker run --rm -v ~/.kube:/home/alitari/.kube/ -it ingress-installer
```


## dev mode

- use [vscode remote-container](https://code.visualstudio.com/docs/remote/containers).
- copy your cluster config in `/home/alitari/.kube/` e.g `cp /workspaces/ingress-installer/.devcontainer/config /home/alitari/.kube/`





