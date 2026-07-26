Bunny Magic Containers is an edge compute platform that runs containerized apps on bare-metal servers globally, placing workloads near users and scaling them based on demand [^1]. It bundles CDN, anycast, load balancing, and auto-scaling [^1].

Deployment options:

| Mode              | What it does                                                                                    | Scaling         |
| ----------------- | ----------------------------------------------------------------------------------------------- | --------------- |
| **Magic**         | AI picks regions and provisions globally                                                        | Auto-scales     |
| **Single region** | Fast deployment in one region you choose                                                        | No auto-scaling |
| **Advanced**      | You choose base and enabled regions; app deploys to enabled regions when users are active there | Auto-scales     |

Before any deployment you must configure a private container registry [^5].

Bunny Database is a managed relational database built on libSQL, a fork of SQLite. It is SQLite-compatible, handles scaling and replication automatically, and spins down when idle [^2]. You connect it to a Magic Containers app by generating tokens in the database Access tab and adding them as secrets; the app then gets the database URL and token as environment variables [^3]. It also exposes an HTTP-based SQL API [^2].

There is a REST API for Magic Containers. Base URL is `https://api.bunny.net/mc`, and it includes an endpoint to deploy applications, so you are not limited to the web UI [^4].

**References**

[^1]: [Magic Containers - bunny.net Documentation](https://docs.bunny.net/magic-containers)

[^2]: [Bunny Database - bunny.net Documentation](https://docs.bunny.net/database)

[^3]: [Meet Bunny Database: the SQL service that just works](https://bunny.net/blog/meet-bunny-database-the-sql-service-that-just-works/)

[^4]: [Magic Containers API Reference - bunny.net Documentation](https://docs.bunny.net/api-reference/magic-containers/overview)

[^5]: [Deploy - bunny.net Documentation](https://docs.bunny.net/magic-containers/deploy)
