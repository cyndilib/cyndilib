from __future__ import annotations

from collections.abc import Iterator
from typing import NamedTuple

import pytest
from _metadata_frame_helpers import get_metadata_frame_data, set_metadata_frame_data
from pugixml_cython.pugixml import Element

from cyndilib import MetadataRecvFrame, MetadataSendFrame


def normalize_xml(xml: str) -> str:
    """Normalize XML string for comparison

    This function removes whitespace and newlines from the XML string
    to make it easier to compare XML strings that may have different
    formatting.
    """
    result = ''.join(xml.split())
    if result.endswith(' />'):
        result = result[:-3] + '/>'
    return result

class XMLResult(NamedTuple):
    tag: str
    attrs: dict[str, str]
    children: list[XMLResult] | None = None
    text: str | None = None
    xpath_query: str | None = None

    def check(self, element: Element, recurse: bool = True) -> None:
        """Check if the given element matches the expected XML result
        """
        assert element.name == self.tag
        assert element.attributes == self.attrs
        if self.text is not None:
            assert element.has_text
            assert element.text is not None
            assert element.text.strip() == self.text
        else:
            assert not element.has_text
        if not recurse:
            return
        if self.children is not None:
            assert len(element) == len(self.children)
            for child_element, child_result in zip(element, self.children):
                child_result.check(child_element, recurse=recurse)
        else:
            assert not len(element)

    def walk(self) -> Iterator[XMLResult]:
        """Walk through the XML result tree and yield each element
        """
        yield self
        if self.children is not None:
            for child in self.children:
                yield from child.walk()


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
    xpath_query=".//ndi_product"
)

XML_STR_3 = """<axis name="id" type="xs:integer" value="1" />"""
XML_RESULT_3 = XMLResult(
    tag="axis",
    attrs={
        "name": "id",
        "type": "xs:integer",
        "value": "1",
    },
    xpath_query=".//axis"
)

XML_STR_4 = """\
<ndi_capabilities
    web_control="http://ndi.video/"
    ntk_ptz="true"
    ntk_exposure_v2="true" />
"""
XML_RESULT_4 = XMLResult(
    tag="ndi_capabilities",
    attrs={
        "web_control": "http://ndi.video/",
        "ntk_ptz": "true",
        "ntk_exposure_v2": "true",
    },
)

XML_STR_5 = """<ndi_capabilities data-type="foo" ndi:state="bar" />"""
XML_RESULT_5 = XMLResult(
    tag="ndi_capabilities",
    attrs={
        "data-type": "foo",
        "ndi:state": "bar",
    },
)

XML_STR_6 = """
<ndi_metadata_group>
    <ndi_tally_echo on_program="true" on_preview="false"/>
    <package type="axis" protocol="FreeD">
        <!-- Timestamp is optional -->
        <timestamp
            name="capture"
            type="xs:dateTimeStamp">2004-04-12T13:20:00.123-05:00
        </timestamp>
        <!-- the naming must be present and unique for the package -->
        <!-- The datatype is mandatory! -->
        <axis name="id" type="xs:integer" value="1" />
        <axis name="posx" type="xs:integer" value="237" />
        <axis name="posy" type="xs:integer" value="9356" />
        <axis name="posz" type="xs:integer" value="44" />
        <axis name="rotx" type="xs:integer" value="23" />
        <axis name="roty" type="xs:integer" value="34" />
        <axis name="rotz" type="xs:integer" value="43" />
        <axis name="zoom" type="xs:integer" value="12" />
        <axis name="focus" type="xs:integer" value="6785" />
        <axis name="iris" type="xs:integer" value="12" />
        <axis name="extender" type="xs:boolean" value="true" />
    </package>
</ndi_metadata_group>
"""
XML_RESULT_6 = XMLResult(
    tag="ndi_metadata_group",
    attrs={},
    xpath_query=".//ndi_metadata_group",
    children=[
        XMLResult(
            tag="ndi_tally_echo",
            attrs={
                "on_program": "true",
                "on_preview": "false",
            },
            xpath_query=".//ndi_metadata_group/ndi_tally_echo"
        ),
        XMLResult(
            tag="package",
            attrs={
                "type": "axis",
                "protocol": "FreeD",
            },
            xpath_query="./ndi_metadata_group/package",
            children=[
                XMLResult(
                    tag="timestamp",
                    attrs={
                        "name": "capture",
                        "type": "xs:dateTimeStamp",
                    },
                    text="2004-04-12T13:20:00.123-05:00",
                    xpath_query="./ndi_metadata_group/package/timestamp",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "id",
                        "type": "xs:integer",
                        "value": "1",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='id']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "posx",
                        "type": "xs:integer",
                        "value": "237",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='posx']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "posy",
                        "type": "xs:integer",
                        "value": "9356",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='posy']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "posz",
                        "type": "xs:integer",
                        "value": "44",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='posz']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "rotx",
                        "type": "xs:integer",
                        "value": "23",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='rotx']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "roty",
                        "type": "xs:integer",
                        "value": "34",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='roty']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "rotz",
                        "type": "xs:integer",
                        "value": "43",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='rotz']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "zoom",
                        "type": "xs:integer",
                        "value": "12",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='zoom']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "focus",
                        "type": "xs:integer",
                        "value": "6785",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='focus']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "iris",
                        "type": "xs:integer",
                        "value": "12",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='iris']",
                ),
                XMLResult(
                    tag="axis",
                    attrs={
                        "name": "extender",
                        "type": "xs:boolean",
                        "value": "true",
                    },
                    xpath_query="./ndi_metadata_group/package/axis[@name='extender']",
                ),
            ],
        ),
    ]
)

@pytest.fixture(params=[
    XMLTestCase(XML_STR_1, XML_RESULT_1),
    XMLTestCase(XML_STR_2, XML_RESULT_2),
    XMLTestCase(XML_STR_3, XML_RESULT_3),
    XMLTestCase(XML_STR_4, XML_RESULT_4),
    XMLTestCase(XML_STR_5, XML_RESULT_5),
])
def metadata_frame_data(request) -> XMLTestCase:
    return request.param

@pytest.fixture(params=[
    XMLTestCase(XML_STR_1, XML_RESULT_1),
    XMLTestCase(XML_STR_2, XML_RESULT_2),
    XMLTestCase(XML_STR_3, XML_RESULT_3),
    XMLTestCase(XML_STR_4, XML_RESULT_4),
    XMLTestCase(XML_STR_5, XML_RESULT_5),
    XMLTestCase(XML_STR_6, XML_RESULT_6),
])
def metadata_frame_data_with_children(request) -> XMLTestCase:
    """Fixture that provides XML test cases with child elements
    """
    return request.param




def test_metadata_frame_benchmark(benchmark, metadata_frame_data: XMLTestCase) -> None:
    """Benchmark MetadataRecvFrame parsing XML data from its frame pointer
    """
    def run_benchmark():
        frame = MetadataRecvFrame()
        set_metadata_frame_data(frame, metadata_frame_data.xml_str)
        tag = frame.get_tag()
        attrs = {k: v for k, v in frame.items()}
        assert tag == metadata_frame_data.expected.tag
        assert attrs == metadata_frame_data.expected.attrs

    benchmark(run_benchmark)


def test_metadata_frame_parse(metadata_frame_data: XMLTestCase) -> None:
    """Test the MetadataRecvFrame's ability to parse XML data from its frame pointer
    """
    frame = MetadataRecvFrame()
    set_metadata_frame_data(frame, metadata_frame_data.xml_str)

    assert frame.get_tag() == metadata_frame_data.expected.tag
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs


def test_metadata_frame_parse_extended(metadata_frame_data_with_children: XMLTestCase) -> None:
    """Test extended metadata frame parsing with child elements and text content
    """
    metadata_frame_data = metadata_frame_data_with_children
    frame = MetadataRecvFrame()
    set_metadata_frame_data(frame, metadata_frame_data.xml_str)

    assert frame.get_tag() == metadata_frame_data.expected.tag
    attrs = {k: v for k, v in frame.items()}
    assert attrs == metadata_frame_data.expected.attrs
    assert frame.root_element is not None
    metadata_frame_data.expected.check(frame.root_element)


def test_metadata_frame_parse_extended_xpath(metadata_frame_data_with_children: XMLTestCase) -> None:
    """Test extended metadata frame parsing with child elements and text content using XPath queries
    """
    metadata_frame_data = metadata_frame_data_with_children
    frame = MetadataRecvFrame()
    set_metadata_frame_data(frame, metadata_frame_data.xml_str)

    doc = frame.xml_doc
    root = frame.root_element
    assert root is not None

    for expected in metadata_frame_data.expected.walk():
        if expected.xpath_query is None:
            continue
        found_elements = doc.xpath_findall(expected.xpath_query)
        assert len(found_elements) == 1
        expected.check(found_elements[0], recurse=False)


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
    assert normalize_xml(xml_data) == normalize_xml(metadata_frame_data.xml_str)


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
    assert normalize_xml(xml_data) == normalize_xml(metadata_frame_data.xml_str)


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
    assert normalize_xml(xml_data) == normalize_xml(metadata_frame_data.xml_str)
