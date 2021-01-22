ddsnet4u
========

A kubernetes `initContainer` to inject additional routes, if needed, into a pod
with a [multus](https://github.com/intel/multus-cni) created interface.  The
approach is generalized but a [Rubin Observatory](https://www.lsst.org/)
specific config file is baked into docker image.  The core functionality and
the config file should be split into separate repos if other uses/users arise.

Usage
-----

A `ddsnet4u` `initContainer` should be used by any pod that needs access to
Rubin "DDS" networks. It should run prior to any other `initContainer`(s) which
assume network access.  As modifying a routing table requires elevated
permissions, the `initContainer` **must** be run as `priviledged`.

```yaml
spec:
  initContainers:
    - name: ddsnet4u
      image: lsstit/ddsnet4u
      securityContext:
        privileged: true
```

See [examples/ddsnet4u-demo.yaml](examples/ddsnet4u-demo.yaml) for a complete example.

Why this exists
---------------

The use case is to support k8s pods running software which needs to communicate
over multicast with peers which may be external to k8s' overlay networks.  The
number of pods which need multicast communication is not fully known in advance
and may be highly dynamic.  In addition, peers are in multiple different
subnets which are all part of the same multicast domain (multicast routing).

Multicast supported was enabled by use of
[multus](https://github.com/intel/multus-cni), which allows the allocation of
an additional pod network interfaces which bypasses k8s' internal networking.
As the default route remains pointed to k8s' overlay, additional static routes
are require to reach all peers.

Multus has multiple [Internet Protocol Address Management (IPAM)
plugins](https://www.cni.dev/plugins/ipam/) to choose from to configure
networking interfaces. These are the currently available options:

* [`host-local`]( https://www.cni.dev/plugins/ipam/host-local/) is able to
  allocate IPs from a predefined pool and manage additional static routes.
  However, pool state is **per node**, which makes this plugin essentially
  unusable on a multinode cluster.

* [`static`](https://www.cni.dev/plugins/ipam/static/) is able to manage static
  routes but requires explicit configuration of the multus interface for every
  pod.  As the number of pods which need a multus managed interface is dynamic,
  this would require the creation some sort of service or control to coordinate
  IP allocation.

* [`dhcp`](https://www.cni.dev/plugins/ipam/dhcp/) is able to obtain a per pod
  DHCP lease from an external DHCP server.  There is no option to use the DHCP
  provided gateway as the default route nor is there the ability to inject
  additional static routes

The `dhcp` plugin best fits the use case but a solution for managing additional
static routes was needed.  Ideally, such support would be added to the upstream
`dhcp` plugin.  However, developing an `initContainer` was considered to be
faster to implement while a solution was urgently needed.  This docker image is
intended to be an interim solution until the ultimate fix in the form of an
ipam plugin may be implemented and deployed.

Goals
-----

* Require minimal configuration at the point of use. Ideally, the only change required
  would the addition of an `initContainer` to the pod `spec`.

* Do nothing and don't explode if the needed routes already exist. This is
  needed to allow transitioning to another solution in the future, such as a
  multus ipam plugin which is capable of managing static routes.

* Fail loudly if the subnet config is absent or specified multus interface
  doesn't exist as a guard against accidental misconfiguration.  This
  effectively means that a pod without a multus interface can not use this
  `initContainer`.
