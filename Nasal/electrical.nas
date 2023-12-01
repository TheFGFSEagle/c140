##
# Procedural model of a Cessna 140 electrical system.  Includes a
# preliminary battery charge/discharge model and realistic ammeter
# gauge modeling.
#

# Reference: https://n140tw.blogspot.com/2014/03/electrical-loads-wiring.html and Flight Manual, especially Figure 19: Electrical Wiring Diagram

var delta_sec		=	props.globals.getNode("/sim/time/delta-sec", 1);

var electrical = props.globals.getNode("/systems/electrical", 1);
var elec_serv  = electrical.getNode("serviceable", 1);
var volts      = electrical.getNode("volts", 1);
var amps       = electrical.getNode("amps", 1);

var nav_equipped    = props.globals.getNode("/sim/equipment/nav-radio", 1);
var astrotech_clock = props.globals.getNode("/sim/equipment/astrotech-lc2", 1);

var clock_power = props.globals.initNode("/instrumentation/clock/powered", 0, "BOOL");
var com_serv    = props.globals.getNode( "/instrumentation/comm[0]/serviceable", 1);
var radio_dim   = props.globals.initNode("/instrumentation/comm[0]/dimming-norm", 0.0, "DOUBLE");
var nav_serv    = props.globals.getNode( "/instrumentation/nav[0]/serviceable", 1);
var tc_spin     = props.globals.getNode( "/instrumentation/turn-indicator/spin", 1);

var ldg_lt_tran = props.globals.getNode( "/controls/lighting/landing-lights-transit", 1);

var circuit_breakers = {
	master:	props.globals.getNode("/controls/circuit-breakers/master", 1),
	generator:	props.globals.getNode("/controls/circuit-breakers/generator", 1),
	radio:	props.globals.getNode("/controls/circuit-breakers/radio", 1),
	ldg_mot:	props.globals.getNode("/controls/circuit-breakers/landing-light-motors", 1),
	ldg_left:	props.globals.getNode("/controls/circuit-breakers/landing-light-left", 1),
	ldg_right:	props.globals.getNode("/controls/circuit-breakers/landing-light-right", 1),
	inst_navlt:	props.globals.getNode("/controls/circuit-breakers/instr-navlt", 1),
	tc:		props.globals.getNode("/controls/circuit-breakers/turn-coordinator", 1),
};

var switches = {
	master:	props.globals.initNode("/controls/switches/master", 0, "BOOL"),
	ext_pwr:	props.globals.initNode("/controls/electric/external-power", 0, "BOOL"),
	starter:	props.globals.initNode("/controls/switches/starter", 0, "BOOL"),
	start_int:	props.globals.getNode( "/controls/engines/engine/starter", 0, "BOOL"),
	tc:		props.globals.initNode("/controls/switches/turn-coordinator", 0, "BOOL"),
	navlt:	props.globals.initNode("/controls/switches/nav-lights", 0, "BOOL"),
};

var output = {
	instr_lt:	electrical.initNode("outputs/instrument-lights", 0.0, "DOUBLE"),
	nav_lt:	electrical.initNode("outputs/nav-lights",        0.0, "DOUBLE"),
	nav_lt_norm:electrical.initNode("outputs/nav-lights-norm",   0,   "BOOL"),
	tc:		electrical.initNode("outputs/turn-indicator", 0.0, "DOUBLE"),
	instr_lt:	electrical.initNode("outputs/instrument-lights", 0.0, "DOUBLE"),
	comm:		electrical.initNode("outputs/comm[0]", 0.0, "DOUBLE"),
	nav:		electrical.initNode("outputs/nav[0]", 0.0, "DOUBLE"),
	ldg_mot:	electrical.initNode("outputs/landing-light-motors", 0.0, "DOUBLE"),
	ldg_left:	electrical.initNode("outputs/landing-light[0]", 0.0, "DOUBLE"),
	ldg_right:	electrical.initNode("outputs/landing-light[1]", 0.0, "DOUBLE"),
	starter:	electrical.initNode("outputs/starter", 0.0, "DOUBLE"),
};

##
# Initialize internal values
#

var ammeter_ave = 0.0;

##
# Battery model class.
#

var BatteryClass = {
	new : func( volt, amps, amp_hours, charge_percent, charge_amps, n){
		m = { 
			parents : [BatteryClass],
			ideal_volts:	volt,
			ideal_amps:	amps,
			volt_p:		electrical.initNode("battery-volts["~n~"]", 0.0, "DOUBLE"),
			amp_hours:	amp_hours,
			charge_percent:	charge_percent, 
			charge_amps:	charge_amps,
		};
		return m;
	},
	apply_load : func( load ) {
		var dt = delta_sec.getDoubleValue();
		var amphrs_used = load * dt / 3600.0;
		var percent_used = amphrs_used / me.amp_hours;
		me.charge_percent -= percent_used;
		if ( me.charge_percent < 0.0 ) {
			me.charge_percent = 0.0;
		} elsif ( me.charge_percent > 1.0 ) {
			me.charge_percent = 1.0;
		}
		var output =me.amp_hours * me.charge_percent;
		return output;
	},
	
	get_output_volts : func {
		var x = 1.0 - me.charge_percent;
		var tmp = -(3.0 * x - 1.0);
		var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
		var output =me.ideal_volts * factor;
		me.volt_p.setDoubleValue( output );
		return output;
	},
	
	get_output_amps : func {
		var x = 1.0 - me.charge_percent;
		var tmp = -(3.0 * x - 1.0);
		var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
		var output =me.ideal_amps * factor;
		return output;
	},
	
	reset_to_full_charge : func {
		me.charge_percent = 1.0;
	},
};


##
# Alternator model class.
#


var AlternatorClass = {
	new: func ( rpm_source, rpm_threshold, ideal_volts, ideal_amps ) {
		var obj = { 
			parents : [AlternatorClass],
			rpm_source : props.globals.getNode( rpm_source, 1),
			rpm_threshold : rpm_threshold,
			ideal_volts : ideal_volts,
			ideal_amps : ideal_amps,
			amps_p:	props.globals.initNode( "/systems/electrical/alternator-amps", 0.0, "DOUBLE"),
		};
		obj.rpm_source.setDoubleValue( 0.0 );
		return obj;
	},
	apply_load: func( amps ){
		var dt = delta_sec.getDoubleValue();
		
		me.amps_p.setDoubleValue( amps );
		
		# Computes available amps and returns remaining amps after load is applied
		# Scale alternator output for rpms < 800.  For rpms >= 800
		# give full output.  This is just a WAG, and probably not how
		# it really works but I'm keeping things "simple" to start.
		var factor = math.min( me.rpm_source.getDoubleValue() / me.rpm_threshold, 1.0 );
		
		# print( "alternator amps = ", me.ideal_amps * factor );
		var available_amps = me.ideal_amps * factor;
		return available_amps - amps;
	},
	get_output_volts: func {
		# Return output volts based on rpm
		
		# scale alternator output for rpms < 800.  For rpms >= 800
		# give full output.  This is just a WAG, and probably not how
		# it really works but I'm keeping things "simple" to start.
		var factor = math.min( me.rpm_source.getDoubleValue() / me.rpm_threshold, 1.0 );
		
		# print( "alternator volts = ", me.ideal_volts * factor );
		return me.ideal_volts * factor;
	},
	get_output_amps: func {
		# Return output amps available based on rpm.
		
		# scale alternator output for rpms < 800.  For rpms >= 800
		# give full output.  This is just a WAG, and probably not how
		# it really works but I'm keeping things "simple" to start.
		var factor = math.min( me.rpm_source.getDoubleValue() / me.rpm_threshold, 1.0 );
		
		# print( "alternator amps = ", ideal_amps * factor );
		return me.ideal_amps * factor;
	},
	
};

# Battery
#	Gill G-25
#		references:		https://www.aircraftspruce.com/catalog/elpages/gillg25.php
#					http://www.gillbatteries.com/Content/specs/G-25.pdf
var battery = BatteryClass.new( 12.0, 30.0, 18.0, 1.0, 7.0, 0);
# Alternator (Starter-Generator)
#	Delco-Remy 15A		ref. https://www.cessna120140.com/wp-content/uploads/2019/06/generator-upgrade.pdf
var alternator = AlternatorClass.new( "/engines/engine/rpm", 500.0, 14.0, 15 );

var reset_battery_and_circuit_breakers = func {
	# Charge battery to 100 %
	battery.reset_to_full_charge();
	
	# Reset circuit breakers
	foreach( var el; keys[ circuit_breakers ] ){
		circuit_breakers.el.setBoolValue( 1 );
	}
}

var reset_electrical = func {
	reset_battery_and_circuit_breakers();
	elec_serv.setBoolValue( 1 );
}

##
# This is the main electrical system update function.
#

var ElectricalSystemUpdater = {
	new : func {
		var m = {
			parents: [ElectricalSystemUpdater]
		};
		# Request that the update function be called each frame
		m.loop = updateloop.UpdateLoop.new(components: [m], update_period: 0.0, enable: 0);
		return m;
	},
	
	enable: func {
		me.loop.reset();
		me.loop.enable();
	},
	
	disable: func {
		me.loop.disable();
	},
	
	reset: func {
		# Do nothing
	},
	
	update: func (dt) {
		update_virtual_bus(dt);
	}
};

##
# Model the system of relays and connections that join the battery,
# alternator, starter, master/alt switches, external power supply.
#

var update_virtual_bus = func (dt) {
	
	var external_volts = 0.0;
	var load = 0.0;
	var battery_volts = 0.0;
	var alternator_volts = 0.0;
	
	if ( elec_serv.getBoolValue() ) {
		battery_volts = battery.get_output_volts();
		alternator_volts = alternator.get_output_volts();
	}
	
	# switch state
	if ( switches.ext_pwr.getBoolValue() ){
		external_volts = 14;
	}
	
	# determine power source
	var bus_volts = 0.0;
	var power_source = nil;
	if ( switches.master.getBoolValue() ) {
		bus_volts = battery_volts;
		power_source = "battery";
		if ( alternator_volts > bus_volts ) {
			bus_volts = alternator_volts;
			power_source = "alternator";
		}
	}
	if ( external_volts > bus_volts ) {
		bus_volts = external_volts;
		power_source = "external";
	}
	
	load += electrical_bus_1( bus_volts );
	
	if ( load > 55 ) {
		# elec_serv.setBoolValue( 0 ); TODO
	}
	
	# system loads and ammeter gauge
	var ammeter = 0.0;
	if ( bus_volts > 1.0 ) {
		# ammeter gauge
		if ( power_source == "battery" ) {
			ammeter = -load;
		} else {
			ammeter = battery.charge_amps;
		}
	}
	
	# charge/discharge the battery
	if ( power_source == "battery" ) {
		battery.apply_load( load, dt );
	} elsif ( bus_volts > battery_volts ) {
		battery.apply_load( -battery.charge_amps, dt );
	}
	
	# filter ammeter needle pos
	ammeter_ave = 0.8 * ammeter_ave + 0.2 * ammeter;
	
	# outputs
	amps.setDoubleValue( ammeter_ave );
	volts.setDoubleValue( bus_volts );
	
	return load;
}


var electrical_bus_1 = func( bv ) {
	var bus_volts = 0.0;
	var load = 0.0;
	
	if ( circuit_breakers.master.getBoolValue() ) {
		bus_volts = bv;
	}
	
	bus_volts = math.max( bus_volts, 0.01 ); # prevent load calculation from failing div/0
	
	# Radio
	if ( circuit_breakers.radio.getBoolValue() ) {
		
		output.comm.setDoubleValue( bus_volts );
		if( bus_volts > 9 ){ 
			com_serv.setBoolValue( 1 );
		} else {
			com_serv.setBoolValue( 0 );
		}
		load += bus_volts / 57;
		
		if( nav_equipped.getBoolValue() ){
			output.nav.setDoubleValue( bus_volts );
			if( bus_volts > 9 ){ 
				nav_serv.setBoolValue( 1 );
			} else {
				nav_serv.setBoolValue( 0 );
			}
			# KX170B power draw
			#	ref. https://www.csobeech.com/files/BK-KX170B-KX175B-Install.pdf, page 1-2
			#		approx. 1.25 A at 13.75 VDC (standby/receive)
			#		max. 5.1 A at 13.75 VDC
			load += 17.2 / bus_volts;
		} else {
			output.nav.setDoubleValue( 0.0 );
			nav_serv.setBoolValue( 0 );
			# KY97A power draw
			#	ref. https://hangar603.org/wp-content/uploads/2018/02/wacoownman-13-ky97ainstallationmanualocr.pdf
			#		approx. 1 A at 13.75 VDC (standby/receive)
			#		approx. 5 A at 13.75 VDC (transmit)
			load += 14.0 / bus_volts;
		}
	} else {
		output.comm.setDoubleValue( 0.0 );
		com_serv.setBoolValue( 0 );
		
		output.nav.setDoubleValue( 0.0 );
		nav_serv.setBoolValue( 0 );
	}
	
	# TODO Load References?!
	
	# Landing Light Motors
	if ( circuit_breakers.ldg_mot.getBoolValue() and ldg_lt_tran.getBoolValue() ) {
		output.ldg_mot.setDoubleValue( bus_volts );
		load += bus_volts / 57;
	} else {
		output.ldg_mot.setDoubleValue( 0.0 );
	}
	
	# Landing Lights
	if ( circuit_breakers.ldg_left.getBoolValue() ) {
		output.ldg_left.setDoubleValue( bus_volts );
		load += bus_volts / 57;
	} else {
		output.ldg_left.setDoubleValue( 0.0 );
	}
	if ( circuit_breakers.ldg_right.getBoolValue() ) {
		output.ldg_right.setDoubleValue( bus_volts );
		load += bus_volts / 57;
	} else {
		output.ldg_right.setDoubleValue( 0.0 );
	}
	
	# Starter Motor
	if ( switches.starter.getBoolValue() ) {
		output.starter.setDoubleValue( bus_volts );
		if(bus_volts > 8){
			switches.start_int.setBoolValue( 1 );
		}else{
			switches.start_int.setBoolValue( 0 );
		}
		load += 24;
	} else {
		output.starter.setDoubleValue( 0.0 );
		switches.start_int.setBoolValue( 0 );
	}
	
	load += inst_nav_bus_1( bus_volts );
	
	# return cumulative load
	return load;
}

var inst_nav_bus_1 = func( bv ) {
	var bus_volts = 0.0;
	var load = 0.0;
	
	# we are fed from the electrical bus 1
	if ( circuit_breakers.inst_navlt.getBoolValue() ) {
		bus_volts = bv;
	}
	
	bus_volts = math.max( bus_volts, 0.01 ); # prevent load calculation from failing div/0
	
	# Turn and Bank Indicator TSI-5550
	#		ref. https://assets.mcico.com/assets/products/ProductFliers/Flier_5550_English.pdf
	#			1.0 A at 14 V = 14.0 W
	#			assume: load lower after spin-up
	if ( circuit_breakers.tc.getBoolValue() and switches.tc.getBoolValue() ) {
		output.tc.setDoubleValue( bus_volts );
		if ( tc_spin.getDoubleValue() < 0.95 ){
			load += 14.0 / bus_volts;
		}else{
			load += 5.0 / bus_volts;
		}
	} else {
		output.tc.setDoubleValue( 0.0 );
	}
	
	# Clock Astrotech LC2
	#		ref. https://www.avtechtyee.com/wp-content/uploads/2020/03/Astrotech-LC-2-Chronometer.pdf
	#			power drain < 0.003 A
	#			assume: 0.002 A at 14 VDC
	if( astrotech_clock.getBoolValue() and bus_volts > 8 ){
		clock_power.setBoolValue( 1 );
		load += 0.028 / bus_volts;
	} else {
		clock_power.setBoolValue( 0 );
	}
	
	# Navigation and Instrument Lights
	#		TODO load reference?!
	if ( switches.navlt.getBoolValue() ) {
		output.instr_lt.setDoubleValue( bus_volts );
		radio_dim.setDoubleValue( 0.5 );
		output.nav_lt.setDoubleValue( bus_volts );
		if( bus_volts > 10 ) {
			output.nav_lt_norm.setBoolValue( 1.0 );
		}else{
			output.nav_lt_norm.setBoolValue( 0.0 );
		}
		load += 4.52;
	} else {
		output.instr_lt.setDoubleValue( 0.0 );
		radio_dim.setDoubleValue( 0.0 );
		output.nav_lt.setDoubleValue( 0.0 );
		output.nav_lt_norm.setBoolValue( 0.0 );
	}
	
	
	# return cumulative load
	return load;
}

##
# Initialize the electrical system
#

var system_updater = ElectricalSystemUpdater.new();

# checking if battery should be automatically recharged
if (!getprop("/systems/electrical/save-battery-charge")) {
	battery.reset_to_full_charge();
};

system_updater.enable();

print("Electrical system initialized");

