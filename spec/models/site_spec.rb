# frozen_string_literal: true

require 'rails_helper'

describe Site do

  context '#determine_user' do
    it "returns current_user if it exists inside of guardian object" do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))

      expect(site.determine_user).to eq(user)
    end

    it "returns nil if no current user exists inside of guardian object" do
      user = nil
      site = Site.new(Guardian.new(user))

      expect(site.determine_user).to eq(nil)
    end

    # there is also another edge case where guardian is nil. i guess this is before a user is signed in...but for the moment i'm not sure how to test this
  end

  describe '#available_icij_projects' do
    it "should return a json containing the id and name of a user's icij project groups" do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))

      icij_group = Fabricate(:icij_group)
      icij_group.add(user)

      result = [{"id"=>icij_group.id, "name"=>icij_group.name}]

      expect(site.available_icij_projects).to eq(result)
    end

    it 'should not return a json object containing the names of groups to which the user is not a member' do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))

      icij_group = Fabricate(:icij_group)
      another_group = Fabricate(:icij_group)
      icij_group.add(user)

      result = [{"id"=>icij_group.id, "name"=>icij_group.name}]

      expect(site.available_icij_projects).to eq(result)
    end

    # when user is not a member of any projects
    it 'returns empty array when user is not a member of any icij project groups' do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))

      icij_group = Fabricate(:icij_group)

      expect(site.available_icij_projects).to eq([])
    end

    # when user is nil
    it 'returns an empty array when the user is nil' do
      user = nil
      site = Site.new(Guardian.new(user))

      icij_group = Fabricate(:icij_group)

      expect(site.available_icij_projects).to eq([])
    end
  end
end
