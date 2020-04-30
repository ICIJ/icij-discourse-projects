# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TopicsController do
  fab!(:topic) { Fabricate(:topic) }
  fab!(:user) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:trust_level_4) { Fabricate(:trust_level_4) }

  describe '#delete' do
    it "won't allow us to delete a topic when we're not logged in" do
      delete "/t/1.json"
      expect(response.status).to eq(403)
    end

    describe 'when logged in' do
      let(:topic) { Fabricate(:topic, user: user, created_at: 48.hours.ago) }
      let!(:post) { Fabricate(:post, topic: topic, user: user, post_number: 1) }

      describe 'without moderator status' do
        # it "succeeds because normal user has permission to delete the topic" do
        #   sign_in(user)
        #   delete "/t/#{topic.id}.json"
        #   expect(response.status).to eq(200)
        # end
      end

      describe 'with moderator status' do
        before do
          sign_in(moderator)
        end

        it 'succeeds' do
          delete "/t/#{topic.id}.json"
          expect(response.status).to eq(200)
          topic.reload
          expect(topic.trashed?).to be_truthy
        end
      end
    end
  end
end
