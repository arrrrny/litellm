import unittest
from unittest.mock import MagicMock, patch
from httpx import Response
from litellm.llms.github_copilot.chat.transformation import GithubCopilotConfig, GithubCopilotError

class TestGithubCopilotConfig(unittest.TestCase):

    @patch("litellm.llms.github_copilot.chat.transformation.httpx.Response")
    def test_transform_response_error_handling(self, MockResponse):
        # Mocking the raw_response
        raw_response = MockResponse()
        raw_response.status_code = 400
        raw_response.json.return_value = {"error": {"message": "Test error message"}}
        raw_response.text = "Test error message"
        raw_response.request.method = "POST"
        raw_response.request.url = "https://api.githubcopilot.com"
        raw_response.request.headers = {"Authorization": "Bearer test_token"}

        config = GithubCopilotConfig()

        with self.assertRaises(GithubCopilotError) as context:
            config.transform_response(
                model="test_model",
                raw_response=raw_response,
                model_response=MagicMock(),
                logging_obj=MagicMock(),
                request_data={},
                messages=[],
                optional_params={},
                litellm_params={},
                encoding=None,
                api_key=None,
                json_mode=None
            )

        self.assertEqual(context.exception.status_code, 400)
        self.assertIn("Test error message", context.exception.message)

    def test_get_error_class(self):
        config = GithubCopilotConfig()
        error = config.get_error_class("Test error", 500, {})
        self.assertIsInstance(error, GithubCopilotError)
        self.assertEqual(error.message, "Test error")
        self.assertEqual(error.status_code, 500)

    def test_get_model_response_iterator(self):
        config = GithubCopilotConfig()
        iterator = config.get_model_response_iterator(
            streaming_response=MagicMock(),
            sync_stream=True,
            json_mode=False
        )
        self.assertIsNotNone(iterator)

if __name__ == "__main__":
    unittest.main()