# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "IMG_SIZE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NUM_GPIO_IN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NUM_GPIO_OUT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NUM_PS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PS0" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PS1" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PS2" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PS3" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PX_BITS" -parent ${Page_0}


}

proc update_PARAM_VALUE.IMG_SIZE { PARAM_VALUE.IMG_SIZE } {
	# Procedure called to update IMG_SIZE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.IMG_SIZE { PARAM_VALUE.IMG_SIZE } {
	# Procedure called to validate IMG_SIZE
	return true
}

proc update_PARAM_VALUE.NUM_GPIO_IN { PARAM_VALUE.NUM_GPIO_IN } {
	# Procedure called to update NUM_GPIO_IN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NUM_GPIO_IN { PARAM_VALUE.NUM_GPIO_IN } {
	# Procedure called to validate NUM_GPIO_IN
	return true
}

proc update_PARAM_VALUE.NUM_GPIO_OUT { PARAM_VALUE.NUM_GPIO_OUT } {
	# Procedure called to update NUM_GPIO_OUT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NUM_GPIO_OUT { PARAM_VALUE.NUM_GPIO_OUT } {
	# Procedure called to validate NUM_GPIO_OUT
	return true
}

proc update_PARAM_VALUE.NUM_PS { PARAM_VALUE.NUM_PS } {
	# Procedure called to update NUM_PS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NUM_PS { PARAM_VALUE.NUM_PS } {
	# Procedure called to validate NUM_PS
	return true
}

proc update_PARAM_VALUE.PS0 { PARAM_VALUE.PS0 } {
	# Procedure called to update PS0 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PS0 { PARAM_VALUE.PS0 } {
	# Procedure called to validate PS0
	return true
}

proc update_PARAM_VALUE.PS1 { PARAM_VALUE.PS1 } {
	# Procedure called to update PS1 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PS1 { PARAM_VALUE.PS1 } {
	# Procedure called to validate PS1
	return true
}

proc update_PARAM_VALUE.PS2 { PARAM_VALUE.PS2 } {
	# Procedure called to update PS2 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PS2 { PARAM_VALUE.PS2 } {
	# Procedure called to validate PS2
	return true
}

proc update_PARAM_VALUE.PS3 { PARAM_VALUE.PS3 } {
	# Procedure called to update PS3 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PS3 { PARAM_VALUE.PS3 } {
	# Procedure called to validate PS3
	return true
}

proc update_PARAM_VALUE.PX_BITS { PARAM_VALUE.PX_BITS } {
	# Procedure called to update PX_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PX_BITS { PARAM_VALUE.PX_BITS } {
	# Procedure called to validate PX_BITS
	return true
}


proc update_MODELPARAM_VALUE.NUM_GPIO_IN { MODELPARAM_VALUE.NUM_GPIO_IN PARAM_VALUE.NUM_GPIO_IN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NUM_GPIO_IN}] ${MODELPARAM_VALUE.NUM_GPIO_IN}
}

proc update_MODELPARAM_VALUE.NUM_GPIO_OUT { MODELPARAM_VALUE.NUM_GPIO_OUT PARAM_VALUE.NUM_GPIO_OUT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NUM_GPIO_OUT}] ${MODELPARAM_VALUE.NUM_GPIO_OUT}
}

proc update_MODELPARAM_VALUE.NUM_PS { MODELPARAM_VALUE.NUM_PS PARAM_VALUE.NUM_PS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NUM_PS}] ${MODELPARAM_VALUE.NUM_PS}
}

proc update_MODELPARAM_VALUE.PS0 { MODELPARAM_VALUE.PS0 PARAM_VALUE.PS0 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PS0}] ${MODELPARAM_VALUE.PS0}
}

proc update_MODELPARAM_VALUE.PS1 { MODELPARAM_VALUE.PS1 PARAM_VALUE.PS1 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PS1}] ${MODELPARAM_VALUE.PS1}
}

proc update_MODELPARAM_VALUE.PS2 { MODELPARAM_VALUE.PS2 PARAM_VALUE.PS2 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PS2}] ${MODELPARAM_VALUE.PS2}
}

proc update_MODELPARAM_VALUE.PS3 { MODELPARAM_VALUE.PS3 PARAM_VALUE.PS3 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PS3}] ${MODELPARAM_VALUE.PS3}
}

proc update_MODELPARAM_VALUE.IMG_SIZE { MODELPARAM_VALUE.IMG_SIZE PARAM_VALUE.IMG_SIZE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.IMG_SIZE}] ${MODELPARAM_VALUE.IMG_SIZE}
}

proc update_MODELPARAM_VALUE.PX_BITS { MODELPARAM_VALUE.PX_BITS PARAM_VALUE.PX_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PX_BITS}] ${MODELPARAM_VALUE.PX_BITS}
}

