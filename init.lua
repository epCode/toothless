local FLAP_FREQUENCY = 0.9 -- time between flaps in seconds

--borrowed from mcl_util
local function set_bone_position(obj, bone, pos, rot) -- sets model bone rotation/position in a better less network using way
	local current_pos, current_rot = obj:get_bone_position(bone)
	local pos_equal = not pos or vector.equals(vector.round(current_pos), vector.round(pos))
	local rot_equal = not rot or vector.equals(vector.round(current_rot), vector.round(rot))
	if not pos_equal or not rot_equal then
		obj:set_bone_position(bone, pos or current_pos, rot or current_rot)
	end
end


local function get_horiz_vel(self) -- returns the sum of x-velocity and y-velocity in their absalute values
  local vel = self.object:get_velocity()
  return math.abs(vel.x)+math.abs(vel.z)
end

local function pon(num) -- Posotive-Or-Negitive
	if num >= 0 then return 1 else return -1 end
end

local function shortest_term_of_yaw_rotation(self, rot_origin, rot_target, nums) -- find the best way to rotate toward a new yaw

	if not rot_origin or not rot_target then
		return
	end

	rot_origin = math.deg(rot_origin)
	rot_target = math.deg(rot_target)

	if rot_origin < rot_target then
		if math.abs(rot_origin-rot_target)<180 then
			if nums then
				return rot_target-rot_origin
			else
				return 1
			end
		else
			if nums then
				return -(rot_origin-(rot_target-360))
			else
				return -1
			end
		end
	else
		if math.abs(rot_origin-rot_target)<180 then
			if nums then
				return rot_target-rot_origin
			else
				return -1
			end
		else
			if nums then
				return (rot_target-(rot_origin-360))
			else
				return 1
			end
		end
	end

end

local function turn_towards(self, yaw, tilt) -- Turn in smoothish incriments towards a certain yaw
  local rot = self.object:get_rotation()
  local newrot = shortest_term_of_yaw_rotation(self, self.object:get_yaw(), yaw, true)
	local roll = rot.z
	if tilt then
		if self.rider or true then
			roll = rot.z+ (-math.rad(newrot)*1.5-rot.z)/200

		else
			roll = -math.rad(newrot) * 2
		end
	else
		roll = -math.rad(newrot)/4
	end
	local newrotround = math.abs(newrot)/newrot
	print(newrotround)
  self.object:set_rotation(vector.new(rot.x,self.object:get_yaw()+newrotround/50,roll))
end


local function dir_to_pitch(dir) -- borrowed from Minclone2
	local xz = math.abs(dir.x) + math.abs(dir.z)
	return -math.atan2(-dir.y, xz)
end

local function take_off(self, moveresult) -- Function for going from a landing/walking position to flying
	if moveresult.touching_ground then --if our feet are on the ground, then jump and set our landed status to false
		self.object:add_velocity(vector.new(0,15,0))
		minetest.after(0.4, function()
			if self and self.object then
				self._landed = false
				self.inversed = 30
			end
		end)
	end
end

local function get_control_power(type, ctrl)
	local power = 0
	if type == "left/right" then
		if ctrl.right then power = power + 1 end
		if ctrl.left then power = power - 1 end
	end
	return power
end

-- [INPUT] --
local function get_input(self, moveresult) -- function to determine how we should fly, if we have a rider, then use player inputs, if not, then use comuter inputs
	local dive, look_yaw, look_pitch, move_dir, controls, hover, flap -- input values
	local pos = self.object:get_pos()

	local follow_pos
	if self.follow then
		follow_pos = self.follow:get_pos()
	end

	if self.rider then -- player input

		look_yaw = self.rider:get_look_horizontal()
		local yaw_input = get_control_power("left/right", self.rider:get_player_control())


		--look_yaw = self.object:get_yaw()+yaw_input
		look_pitch = self.rider:get_look_vertical()



		controls = self.rider:get_player_control()

		hover = controls.sneak
		flap = controls.jump
		dive = controls.up
	else -- computer-input/mob function
		if minetest.get_player_by_name("singleplayer") then
			self.follow = minetest.get_player_by_name("singleplayer")
		else
			self.follow = nil
		end
		controls = {}
		if self._landed then -- If we are walking (not flying)
			if self.follow then -- if we are following someone or something self.follow = ObjectRef

				local distance_to_follow = vector.distance(pos, follow_pos) -- vector direction to follow
				local dir = vector.direction(pos, follow_pos)
				local to_yaw = self.object:get_yaw()-minetest.dir_to_yaw(dir)
				local to_pitch = dir_to_pitch(dir)-self.object:get_rotation().x
				set_bone_position(self.object, "Head_Control", vector.new(0,0,0), vector.new(math.deg(to_pitch),0,math.deg(to_yaw))) -- Look at player
				if distance_to_follow > 15 then -- we are too far away from follow
					self.object:add_velocity(vector.new(dir.x, 0, dir.z))

				elseif distance_to_follow < 7 then -- if we are too close to follow
					--TODO runaway and then take off
					if get_horiz_vel(self) > 8 then -- if follow is chasing us too fast, take off then circle back around
						take_off(self, moveresult)
					end
					self.object:add_velocity(vector.new(-dir.x, 0, -dir.z)) -- Get away from follow, too close
				else -- if we are far enough away from follow and close enough that we can just stay where we are
					local dir = vector.direction(pos, follow_pos)
					local newrot = shortest_term_of_yaw_rotation(self, self.object:get_yaw(), minetest.dir_to_yaw(dir), true)

					if self._constant_walk then -- Walk around follow in circles sometimes
						self.object:add_velocity(vector.multiply(minetest.yaw_to_dir(self.object:get_yaw()), 0.27))
					end

					if math.abs(newrot) > 75 then -- never face body away from follow while standing
						turn_towards(self, minetest.dir_to_yaw(dir), false)
					end
				end
			end
		else -- flying brain
			set_bone_position(self.object, "Head_Control", vector.new(0,0,0), vector.new(0,0,0)) -- reset head rot and pos

			--default most inputs false or self
			look_pitch = self.object:get_rotation().x
			look_yaw = self.object:get_yaw()
			flap = false
			hover = false
			dive = true

			self.desired_altitude = 10 -- default desired hight


			if self.follow and self.inversed and self.inversed > 0 then -- fly away from follow after we just took off in fear
				self.desired_altitude = self.follow:get_pos().y+20
				self.goto_pos = vector.add(vector.multiply(vector.direction(self.follow:get_pos(), pos), 10), pos)
				self.inversed = self.inversed - 0.23
			elseif self.follow then -- fly towards follow
				self.desired_altitude = self.follow:get_pos().y+8 -- fly around 8 blocks above the follows head
				self.goto_pos = self.follow:get_pos()
			end


			if self.goto_pos then -- if we have a destination then turn toward it
				look_yaw = minetest.dir_to_yaw(vector.direction(pos, self.goto_pos)) -- yaw look input
				look_pitch = -dir_to_pitch(vector.direction(pos, self.goto_pos)) -- pitch look input
			end

			if self.follow and self.follow:get_pos().y > pos.y then -- if we are lower than we should be flap
				flap = true -- jump/flap input
			end
			local raycast = minetest.raycast(pos, vector.add(pos, vector.new(0,-64,0)), false, false) -- raycast to determine height above ground
			for hitpoint in raycast do
				if hitpoint.type == "node" then
					local ground_pos = hitpoint.under
					if ground_pos.y < pos.y and pos.y-ground_pos.y < self.desired_altitude then -- we are too close to the ground fly up
						if self.follow and vector.distance(self.follow:get_pos(), pos) < 20 and self.follow:get_pos().y < self.object:get_pos().y or not self.follow then -- if we are close to follow no need to flap so hard, just hover
							hover = true
							flap = false
						end
					end
				end
			end

		end

	end

	if self._constant_walk and math.random(20) == 1 then -- random walk chance
		self._constant_walk = nil
	elseif math.random(20) == 1 then
		self._constant_walk = true
	end


	return {dive=dive, look_yaw=look_yaw, look_pitch=look_pitch, move_dir=move_dir, controls=controls, hover=hover, flap=flap} -- return inputs
end


local function fallspeed(self, amount) -- ability to change only y-velocity
  local vel = self.object:get_velocity()
  self.object:set_velocity({x=vel.x,y=amount,z=vel.z})
end


local function set_animation(self, name) -- dynamically change our animation
  if not self.animations[name] then return end
	local R, M, S, K = self.object:get_animation()
  if R.x == self.animations[name][1].x then return end
  self.object:set_animation(self.animations[name][1], 30, 0.15, self.animations[name][2])
end


local function fade_pitch(self, pitch) -- change pitch smoothishly
	local rot = self.object:get_rotation()
  self.object:set_rotation(vector.new(rot.x+(pitch-rot.x)/30,rot.y,rot.z))
end

minetest.register_entity("toothless:night_fury", {
  visual = "mesh",
  mesh = "toothless.b3d",
  textures = {"toothless.png"},
  collisionbox = {-1.5,-0.1,-1.5,1.5,1.5,1.5},
  physical = true,
	collide_with_objects = false,
  animations = {
    fly_straight = {{x=41, y=60}, true},
    flap = {{x=62, y=87}, true},
    air_break = {{x=101, y=124}, true},
    dive = {{x=90, y=99}, true},
    walk_normal = {{x=126, y=147}, true},
    run = {{x=149, y=166}, true},
  },
	stepheight = 2.1,
  visual_size = {x=80,y=80},


  velticker = 0,
  _speed_add_from_fall = 1,
  flap_timer = 0,
  on_deactivate = function(self) -- make sure that when a player is demounted from riding, that thier camera positioning is fixed
    if self.rider then
      self.rider:set_eye_offset(vector.new(0,0,0), vector.new(0,0,0))
    end
  end,
  on_detach_child = function(self, child)
    if child:is_player() then
      child:set_eye_offset(vector.new(0,0,0), vector.new(0,0,0))
			child:set_properties({visual_size = {x=1,y=1}})
			child:set_look_roll(0)
      self.rider = nil
    end
  end,
	on_activate = function(self)
		set_animation(self, "fly_straight")
	end,
  on_rightclick = function(self, clicker) -- manage riders
    if not clicker or not clicker:is_player() or self.rider and self.rider ~= clicker then return end

    if self.rider then -- if there is already a rider then get him off
      self.rider:set_detach()
      self.rider = nil
    else -- mount the player
      self.rider = clicker
      self.rider:set_properties({visual_size={x=0.014,y=0.014}})
      self.rider:set_eye_offset(vector.new(0,15,-5), vector.new(0,5,-5))
      self.rider:set_attach(self.object, "Body", vector.new(0,0,-0.03), vector.new(90,0,180), false)
    end
  end,
  on_step = function(self, dtime, moveresult)


		local input = get_input(self, moveresult)
		local vel = self.object:get_velocity()
		if moveresult.touching_ground then
			self._landed = true
		elseif vel.y < -1 and input.flap and self._landed==true then
			self._landed = false
			set_animation(self, "fly_straight")
		end

    if not self._landed then -- Flying  Mechanics


      self.flap_timer = self.flap_timer + dtime



      turn_towards(self, input.look_yaw, true)

			if self.rider then
				local getlookroll = self.rider:get_look_roll()
				self.rider:set_look_roll(getlookroll+(self.object:get_rotation().z-getlookroll)/5)
			end
      self.object:set_rotation({x=-input.look_pitch, y=self.object:get_yaw(), z=self.object:get_rotation().z})



      local pitch, yaw = self.object:get_rotation().x, self.object:get_yaw()
      local flydir = minetest.yaw_to_dir(yaw)


			if pitch < -1 and vel.y < -5 and input.dive then
				self._diving = true
			else
				self._diving = false
			end

      if pitch < 0.3 or input.hover then
			  self.object:set_velocity( vector.new(vel.x*0.97, vel.y, vel.z*0.97) ) -- diffuse horrizontal speed
			  self.object:add_velocity( vector.multiply(flydir, (1.7- -pitch)*0.5 * self._speed_add_from_fall) ) -- horrizontal speed
      else
        self.object:set_velocity( vector.new(vel.x*0.98, vel.y*0.98, vel.z*0.98) ) -- diffuse horrizontal speed
        self.object:add_velocity( vector.new(0,pitch*get_horiz_vel(self)/20,0) ) -- horrizontal speed
      end



      self.object:set_acceleration({x=0,y=-20,z=0}) -- set_gravity


      local needed_yspeed = math.abs(pitch)*17 -- how fast should we be falling with wings spread
			-- ANIMATION on ground
      if pitch > 0.3 then -- flying up? or way down?
        needed_yspeed = 1
      elseif self._diving then
        needed_yspeed = 1000
      end

      if vel.y < -needed_yspeed then -- cap falling speed
        fallspeed(self, vel.y*0.85)
      end
      self._speed_add_from_fall = 1
      if self._old_speed then -- Physics
        if self._old_speed-self.object:get_velocity().y < -0.34 then
          self._speed_add_from_fall = 3
        end
      end


      if self.flap_timer > FLAP_FREQUENCY and input.flap then --If space pressed, flap foward
        self.flap_timer = 0
        set_animation(self, "flap")
        minetest.after(0.36,function()
          if self and self.object then
            self.object:add_velocity(vector.new(vel.x*0.1+flydir.x*10, 15, vel.z*0.1+flydir.z*10))
          end
        end)
			elseif self.flap_timer > FLAP_FREQUENCY and input.hover then -- If sneak pressed hover
				self.flap_timer = 0
				set_animation(self, "air_break")
				minetest.after(0.36,function()
					if self and self.object then
						self.object:add_velocity(vector.new(vel.x*0.1+flydir.x*-10, 15, vel.z*0.1+flydir.z*-10))
					end
				end)
      elseif self.flap_timer > FLAP_FREQUENCY then -- If we are diving switch to diving animation else glide
        if self._diving then
          set_animation(self, "dive")
        else
          set_animation(self, "fly_straight")
        end
      end
			--self.object:set_animation_frame_speed(30)

      self._old_speed = self.object:get_velocity().y -- physics data
		elseif self._landed then

			local controls = input.controls
			self.object:set_acceleration({x=0,y=-20,z=0})

			local sprint = 1
			if controls.aux1 then sprint = 1.6 end

			local moveF_vel = vector.new(0,0,0)
			if self.rider then
				moveF_vel = vector.multiply(minetest.yaw_to_dir(self.rider:get_look_horizontal()), 0.7*sprint)
			end
			if controls.up then
				self.object:add_velocity(moveF_vel)
			end
			if controls.down then
				self.object:add_velocity(vector.multiply(moveF_vel, -1))
			end
			if controls.right then
				self.object:add_velocity(vector.rotate_around_axis(moveF_vel, vector.new(0,1,0), -1.57))
			end
			if controls.left then
				self.object:add_velocity(vector.rotate_around_axis(moveF_vel, vector.new(0,1,0), 1.57))
			end

			if controls.jump and moveresult.touching_ground then
				self.object:add_velocity(vector.new(0,20,0))
			end

			local vel = self.object:get_velocity()



			fade_pitch(self, dir_to_pitch(vel))

			if self.rider then
				turn_towards(self, minetest.dir_to_yaw(vel), false)
			end

			if get_horiz_vel(self) > 17 then -- ANIMATION on ground
				set_animation(self, "run")
				self.object:set_animation_frame_speed(get_horiz_vel(self)*2)
			elseif get_horiz_vel(self) > 0.3 then
				set_animation(self, "walk_normal")
				self.object:set_animation_frame_speed(get_horiz_vel(self)*4.8)
			end
			self.object:set_velocity( vector.new(vel.x*0.93, vel.y, vel.z*0.93) ) -- diffuse horrizontal speed
    end

		if math.deg(self.object:get_yaw()) > 360 then
			self.object:set_yaw(math.rad(0))
		elseif math.deg(self.object:get_yaw()) < 0 then
			self.object:set_yaw(math.rad(360))
		end

  end,
})
