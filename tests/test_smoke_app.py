# tests/test_smoke_app.py
import os

import pytest
from selenium import webdriver
from selenium.webdriver.common.by import By


@pytest.fixture
def browser():
    """Return a headless Chrome browser instance."""
    options = webdriver.ChromeOptions()
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    driver = webdriver.Chrome(options=options)
    yield driver
    driver.quit()


def test_smoke_home_loads(browser):
    """SMOKE: Home page loads and contains a prediction form."""
    app_url = os.environ.get("APP_BASE_URL", "http://localhost:8000")
    browser.get(app_url + "/")
    assert browser.title is not None
    assert browser.find_element(By.TAG_NAME, "form") is not None


def test_smoke_health_endpoint(browser):
    """SMOKE: /health endpoint responds with OK."""
    app_url = os.environ.get("APP_BASE_URL", "http://localhost:8000")
    browser.get(app_url + "/health")
    assert "OK" in browser.page_source
