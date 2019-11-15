require 'rails_helper'
require_dependency 'site'

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

  describe '#icij_project_names' do
    context "user belong to icij project groups" do
      it "returns an array of the user's icij project group names, after determining the user" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))
        icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect(site.icij_project_names).to eq([icij_group.name])

        user = nil
        site = Site.new(Guardian.new(user))

        expect(site.icij_project_names).to eq([])
      end

      it "does not return the names of icij project groups to which the user is not a member" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))
        icij_group = Fabricate(:icij_group)
        another_icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect(site.icij_project_names).to eq([icij_group.name])
      end
    end
  end

  describe '#fellow_icij_project_members' do
    context 'user is nil' do
      it "returns an empty array" do
        user = nil
        site = Site.new(Guardian.new(user))

        expect(site.fellow_icij_project_members).to eq([])
      end
    end

    context 'user is not a member of any projects' do
      it 'returns an empty array' do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)

        expect(site.fellow_icij_project_members).to eq([])
      end
    end

    context 'user is the only project member' do
      it "returns the user's id alone in an array" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect(site.fellow_icij_project_members).to eq([user.id])
      end

      it "does not return users with negative ids (programmatic users)" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect((site.fellow_icij_project_members).all?(&:positive?)).to eq(true)
      end
    end

    context 'multiple project members' do
      it "returns the ids in an array" do
        user = Fabricate(:user)
        another_user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)
        icij_group.add(another_user)

        expect(site.fellow_icij_project_members).to eq([user.id, another_user.id])
      end

      it "does not return users with negative ids (programmatic users)" do
        user = Fabricate(:user)
        another_user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)
        icij_group.add(another_user)

        expect((site.fellow_icij_project_members).all?(&:positive?)).to eq(true)
      end
    end
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

  describe '#icij_project_categories' do
    it "returns an array of ids for the categories that exist inside of a user's icij project groups" do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))


      icij_group = Fabricate(:icij_group)
      icij_group.add(user)

      private_cat = Fabricate(:category)
      Fabricate(:topic, category: private_cat)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      expect(site.icij_project_categories).to eq([private_cat.id])
    end

    it "does not return an array containing the category ids for categories that are not in the user's icij project groups" do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))


      icij_group = Fabricate(:icij_group)
      icij_group.add(user)

      another_icij_group = Fabricate(:icij_group)

      private_cat = Fabricate(:category)
      Fabricate(:topic, category: private_cat)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      another_private_cat = Fabricate(:category)
      Fabricate(:topic, category: another_private_cat)
      another_private_cat.set_permissions(another_icij_group.id => 1)
      another_private_cat.save

      expect(site.icij_project_categories).to_not include(another_private_cat.id)
    end

    it "returns empty array when user is nil" do
      user = nil
      site = Site.new(Guardian.new(user))


      icij_group = Fabricate(:icij_group)

      private_cat = Fabricate(:category)
      Fabricate(:topic, category: private_cat)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      expect(site.icij_project_categories).to eq([])
    end

    it "returns empty array when user is not in any icij project groups" do
      user = Fabricate(:user)
      site = Site.new(Guardian.new(user))


      icij_group = Fabricate(:icij_group)

      private_cat = Fabricate(:category)
      Fabricate(:topic, category: private_cat)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      expect(site.icij_project_categories).to eq([])
    end
  end
end
