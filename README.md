# VHDL FSM Visualizer
A VHDL helper that visualizes FSM states and transitions by tracking, in real-time, a specified .vhd file. The purpose of this application is to provide a user friendly interface for mapping an FSM at the same time it is coded, in VHDL. It aims to accelerate FSM creation and debugging by visualizing its states and flow.

##Current Goals
*	Support for mapping conditional state transitions
* User friendly interface that accelerates development & debugging

##Future Goals
*	Support for visualising multiple FSMs in the same .vhd file
* Support for tracking multiple .vhd files through an MDI (multiple document interface)
* Embedded VHDL text editor

###How To: Use the provided VHDL files to test the application
There are two demo files provided for using with the application and they are located in **VHDL_FSM_Visualizer/Demo Files/**
*	**sdram_ctrl_de2_tb.vhd** has an enum type for FSM defined as **fsm_state_type**. There is only one variable on which the FSM is switched and it is named **state**
* **video_composer_fsmd.vhd** has an enum type for FSM defined as **State_Type**. There are two variables on which the FSM is switched and there are named respectively **current_state** and **next_state**.
