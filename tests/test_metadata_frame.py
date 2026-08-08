from __future__ import annotations

from typing import NamedTuple

import pytest
from _metadata_frame_helpers import get_metadata_frame_data, set_metadata_frame_data

from cyndilib import MetadataRecvFrame, MetadataSendFrame
from cyndilib.metadata_frame import parse_xml


class XMLResult(NamedTuple):
    tag: str
    attrs: dict[str, str]


class XMLTestCase(NamedTuple):
    xml_str: str
    expected: XMLResult


XML_STR_1 = """<ndi_tally_echo on_program="true" on_preview="false"/>"""
XML_RESULT_1 = XMLResult(
    tag="ndi_tally_echo",
    attrs={
        "on_program": "true",
        "on_preview": "false",
    },
)


XML_STR_2 = """<ndi_product long_name="NDILib Receive Example" short_name="NDILib Receive" manufacturer="CoolCo, inc." version="1.000.000" model_name="PBX-42Q" session_name="My Midday Show" serial="ABCDEFG"/>"""
XML_RESULT_2 = XMLResult(
    tag="ndi_product",
    attrs={
        "long_name": "NDILib Receive Example",
        "short_name": "NDILib Receive",
        "manufacturer": "CoolCo, inc.",
        "version": "1.000.000",
        "model_name": "PBX-42Q",
        "session_name": "My Midday Show",
        "serial": "ABCDEFG",
    },
)

@pytest.fixture(params=[
    XMLTestCase(XML_STR_1, XML_RESULT_1),
    XMLTestCase(XML_STR_2, XML_RESULT_2),
])
def metadata_frame_data(request) -> XMLTestCase:
    return request.param

def test_parse_xml(metadata_frame_data: XMLTestCase) -> None:
    """Test the parse_xml function with various XML strings
    """
    tag, attrs = parse_xml(metadata_frame_data.xml_str)
    assert tag == metadata_frame_data.expected.tag
    assert attrs == metadata_frame_data.expected.attrs


def test_metadata_frame_parse(metadata_frame_data: XMLTestCase) -> None:
    """Test the MetadataRecvFrame's ability to parse XML data from its frame pointer
    """
    frame = MetadataRecvFrame()
    set_metadata_frame_data(frame, metadata_frame_data.xml_str)

    assert frame.get_tag() == metadata_frame_data.expected.tag
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs


def test_metadata_send_frame_setters(metadata_frame_data: XMLTestCase) -> None:
    """Test the MetadataSendFrame's ability to set XML data and retrieve it

    Using the setters methods for tag and attributes
    """
    frame = MetadataSendFrame(tag='')
    frame.set_tag(metadata_frame_data.expected.tag)
    assert frame.get_tag() == metadata_frame_data.expected.tag
    frame.update(metadata_frame_data.expected.attrs)
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs
    xml_data = get_metadata_frame_data(frame)
    assert xml_data == metadata_frame_data.xml_str


def test_metadata_send_frame_init(metadata_frame_data: XMLTestCase) -> None:
    """Test the MetadataSendFrame's ability to set XML data and retrieve it

    Using the constructor to set the tag and attributes
    """
    frame = MetadataSendFrame(
        tag=metadata_frame_data.expected.tag,
        initdict=metadata_frame_data.expected.attrs
    )
    assert frame.get_tag() == metadata_frame_data.expected.tag
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs
    xml_data = get_metadata_frame_data(frame)
    assert xml_data == metadata_frame_data.xml_str


def test_metadata_send_frame_init_with_kwargs(metadata_frame_data: XMLTestCase) -> None:
    """Test the MetadataSendFrame's ability to set XML data and retrieve it

    Using the constructor to set the tag and attributes with keyword arguments
    """
    frame = MetadataSendFrame(
        tag=metadata_frame_data.expected.tag,
        **metadata_frame_data.expected.attrs
    )
    assert frame.get_tag() == metadata_frame_data.expected.tag
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs
    xml_data = get_metadata_frame_data(frame)
    assert xml_data == metadata_frame_data.xml_str
