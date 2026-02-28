## CCSDS Serial Interface

#### Description

This directory currently contains one serial interface component (`Ccsds_Serial_Interface`). This component is meant to be a "backdoor" serial
component which uses Ada.Text_IO to send and receive data over a serial port. On Linux, this will send/recv data 
to/from the terminal, but Ada.Text_IO is attached to a diagnostic uart on most embedded systems. This means that
this component can be used as a quick and dirty serial interface without implementing hardware specific uart drivers.

#### Internal State

The `Cpu_Usage` and `Count` fields that previously existed in the instance record have been removed. The CPU-usage measurement was dead code — computed but never exported via any data-product connector. If CPU-usage monitoring of the listener task is needed, a data-product connector should be added to the component model.

