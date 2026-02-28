## CCSDS Serial Interface

#### Description

This directory currently contains one serial interface component (`Ccsds_Serial_Interface`). This component is meant to be a "backdoor" serial
component which uses Ada.Text_IO to send and receive data over a serial port. On Linux, this will send/recv data 
to/from the terminal, but Ada.Text_IO is attached to a diagnostic uart on most embedded systems. This means that
this component can be used as a quick and dirty serial interface without implementing hardware specific uart drivers.

#### Internal State

The component instance record contains the following internal fields:

- **`Count`** — A packet counter used to trigger periodic CPU-usage measurement of the listener task. Every 200 received packets, the listener's CPU time is sampled.
- **`Cpu_Usage`** — Stores the computed CPU-usage percentage of the listener task. This represents the execution margin available on the system when the listener is set to lowest priority. *Note:* This value is currently computed internally but is not exported via any data-product connector.

