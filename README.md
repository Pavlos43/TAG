# TAG

TAG is a TinyOS wireless sensor network application that builds a routing tree and performs periodic in-network aggregation. It supports a root node that selects an aggregate function and epoch duration, distributes those parameters through the network, and collects sensor values upward through parent-child links.

## Features

- Automatic routing-tree construction
- Parent selection and tree-depth-based communication scheduling
- Per-epoch sensor value updates
- In-network aggregation for:
  - Sum
  - Average
  - Variance
  - Maximum
- Packet queues for routing and value messages
- TOSSIM simulation support
- Optional serial communication and debug printf support

## Repository Layout

```text
code/
├── SRTreeAppC.nc          # TinyOS application wiring
├── SRTreeC.nc             # Routing tree and aggregation implementation
├── SimpleRoutingTree.h    # Packet formats and configuration constants
├── PacketQueue.nc/.C      # Packet queue interface and implementation
├── Makefile               # TinyOS build configuration
├── mySimulation.py        # TOSSIM simulation driver
├── generateTop.py         # Topology generation helper
├── topology.txt           # Example sensor-network topology
├── app.xml                # TOSSIM application configuration
└── README                 # Original project notes
```

## How It Works

Node `0` acts as the root. It randomly chooses one aggregation function and an epoch duration, then broadcasts routing messages containing the tree depth and packed configuration.

Other motes receive the broadcast, select the first reachable sender as their parent, calculate their depth, and rebroadcast the routing information. Once the tree is established, nodes wake according to their depth and transmit one value per epoch to their parent.

At each node, the aggregate is built from the node's current sensor value and the latest values received from its children. The root prints the final result for the epoch.

## Sensor Aggregations

| Function | Output |
|---|---|
| Sum | Sum of all node values |
| Average | Mean of all node values |
| Variance | Population variance of node values |
| Maximum | Largest value in the network |

Sensor values are initially randomized between `1` and `100`. Between epochs, a node changes its value by up to 25% of its previous value while keeping it within the configured range.

## Requirements

- TinyOS toolchain
- TinyOS support for the target mote platform
- Python 2 for the included TOSSIM Python driver
- TOSSIM bindings such as `_TOSSIMmodule.so` and `TOSSIM.py`

## Build and Install

Enter the `code` directory before running TinyOS make commands:

```bash
cd code
```

Build for an Iris mote and install it through a MIB520 interface:

```bash
make iris install,0 mib520,/dev/ttyUSB0
```

Replace node ID `0` and the serial device when appropriate.

List connected motes:

```bash
motelist
```

Listen to serial data:

```bash
java net.tinyos.tools.Listen -comm serial@/dev/ttyUSB0:iris
```

## Run a TOSSIM Simulation

Build the Micaz TOSSIM target:

```bash
make micaz sim
```

Run the simulation with the default topology:

```bash
python mySimulation.py
```

You can provide a topology file, number of nodes, random delay, and random seed:

```bash
python mySimulation.py topology.txt 10 3 12345
```

The simulation prints boot, radio, routing, and aggregation output for 800 seconds of simulated time.

## Build Flags

Defined in `code/Makefile`:

- `SERIAL_EN` — Enables serial communication support.
- `PRINTFDBG_MODE` — Enables TinyOS debug printf output. It should not be enabled for TOSSIM builds.

## Notes

- The compiled TOSSIM artifacts and Python bindings in `code/` are platform-specific and may need to be rebuilt in the target environment.
- Node `0` is the root and defines the aggregation function and epoch duration for the network.
- The original project notes are available in [`code/README`](code/README).
