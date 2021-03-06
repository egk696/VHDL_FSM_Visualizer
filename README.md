# VHDL FSM Visualizer
A VHDL helper that visualizes FSM states and transitions by tracking, in real-time, a specified .vhd file. The purpose of this application is to provide a user friendly interface for mapping an FSM at the same time it is coded, in VHDL. It aims to accelerate FSM creation and debugging by visualizing its states and flow. The application can also be used for educational purposes to help understand better the concept of FSMs by visualising their graph as you code them.

## Current Goals
* Live file tracking and auto-update
*	Support for mapping conditional state transitions
* User friendly interface that accelerates debugging & learning

## Future Goals
* Support for visualising FSM controlled outputs
*	Support for visualising multiple FSMs in the same .vhd file
* Support for tracking multiple .vhd files through an MDI (multiple document interface)
* Embedded VHDL text editor

### How to: Use the application
1. Fill in the 3 textboxes **Enum type**, **Current State Variable Name**, **Next State Variable Name** with the respective names found in the .vhd file you wish to load.
2. Load a .vhd file, either from the those provided or one of your own. 
*Note: Make sure the file contains an FSM named accordingly to the parameters specified in Step 1*
3. Now the file you loaded is automatically tracked and any changes you perform will also update the FSM graph in the VHDL FSM Visualizer application.

### How To: Use the provided VHDL files to test the application
There are 4 demo files provided for using along with the application and they are located in VHDL_FSM_Visualizer/Demo Files/

* **sdram_ctrl_de2_tb.vhd** has an enum type for FSM defined as **fsm_state_type**. There is only one variable that controls the transitions of the FSM (Moore), named **state**.
* **video_composer_fsmd.vhd** has an enum type for FSM defined as **State_Type**. There are two variables that control the transitions of the FSM (Latched Mealy), named **current_state** and **next_state** respectively.
* **mealy_4s.vhd** has an enum type for FSM defined as **state_type**. There is only one variable that controls the transitions of the FSM, named **state**.
* **moore_4s.vhd** has an enum type for FSM defined as **state_type**. There is only one variable that controls the transitions of the FSM, named **state**.
