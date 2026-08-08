from libc.string cimport strcpy
# cimport lxml.includes.etreepublic as cetree
# cdef object etree
# from lxml import etree
# cetree.import_lxml__etree()

# import xml.etree.ElementTree as ET
import re


__all__ = ('MetadataFrame', 'MetadataRecvFrame', 'MetadataSendFrame')


cdef object DOC_PATTERN = re.compile(r'<(?P<tag>[A-Za-z_:][\w:.-]*)\s*(?P<attrs>[^>]*?)\s*\/>')
cdef object ATTR_PATTERN = re.compile(r'(?:^|\s+)(?P<name>\w+)="(?P<value>[^"]*)"')


def parse_xml(str xml):
    cdef object m = DOC_PATTERN.match(xml)
    if m is None:
        return None, None
    cdef str tag = m['tag'], attr_str = m['attrs']
    cdef dict attrs = {}, d

    # cdef str key, value

    for m in ATTR_PATTERN.finditer(attr_str):
        print(f'm: {m!r}')
        d = m.groupdict()
        key = d['name']
        if key is None:
            continue
        value = d['value']
        if value is None:
            continue
        attrs[key] = value
    return tag, attrs


cdef class MetadataFrame:
    """An |NDI| metadata frame

    Metadata frames carry miscellaneous information between sources and receivers
    formatted as a single XML tag.

    The data can be application-specific although there are some reserved
    namespaces and tag names for standardized use:

    .. code-block:: xml

        <ndi_tally_echo on_program="true" on_preview="false"/>

        <ndi_product long_name="NDILib Receive Example"
                     short_name="NDILib Receive"
                     manufacturer="CoolCo, inc."
                     version="1.000.000"
                     model_name="PBX-42Q"
                     session_name="My Midday Show"
                     serial="ABCDEFG"/>

    This class provides an interface to the parsed xml data with the attributes
    available in the :attr:`attrs` attribute or through dict-like methods::

        >>> metadata_frame['on_program']
        'true'
        >>> metadata_frame.get('on_preview')
        'false'

    Attributes:
        tag (str): The xml tag name
        attrs (dict): The xml attributes

    """
    def __cinit__(self, *args, **kwargs):
        self.ptr = metadata_frame_create()
        self.xml_bytes = b''

    def __init__(self, *args, **kwargs):
        self.tag = None
        self.attrs = {}

    def __dealloc__(self):
        cdef NDIlib_metadata_frame_t* p = self.ptr
        self.ptr = NULL
        if p is not NULL:
            metadata_frame_destroy(p)

    def get_tag(self):
        """Get the xml tag name for this metadata frame
        """
        return self.tag

    def set_tag(self, str tag):
        """Set the xml tag name for this metadata frame
        """
        self.tag = tag

    def get(self, str tag):
        """Get the value of the attribute with the given name
        """
        return self.attrs.get(tag)

    def keys(self):
        """Get the attribute names for this metadata frame

        .. versionadded:: 0.1.2
        """
        return self.attrs.keys()

    def values(self):
        """Get the attribute values for this metadata frame

        .. versionadded:: 0.1.2
        """
        return self.attrs.values()

    def items(self):
        """Get the attribute name-value pairs for this metadata frame

        .. versionadded:: 0.1.2
        """
        return self.attrs.items()

    def __getitem__(self, str key):
        return self.attrs[key]

    cdef char* _get_data(self) nogil:
        return self.ptr.p_data
    cdef void _set_data(self, char* data) nogil:
        self.ptr.p_data = data

    def get_timecode_posix(self):
        """Get the current :term:`timecode <ndi-timecode>` converted to float
        seconds (posix)

        .. versionadded:: 0.1.2
        """
        cdef double r = ndi_time_to_posix(self.ptr.timecode)
        return r

    def get_timecode(self):
        """Get the current :term:`timecode <ndi-timecode>` as an integer
        """
        return self._get_timecode()

    cdef int64_t _get_timecode(self) nogil:
        return self.ptr.timecode
    cdef void _set_timecode(self, int64_t value) nogil:
        self.ptr.timecode = value

    def __repr__(self):
        return f'<{self.__class__.__name__}: "{self}">'

    def __str__(self):
        return self.xml_bytes.decode('UTF-8')


cdef class MetadataRecvFrame(MetadataFrame):
    """A MetadataFrame used in :class:`.receiver.Receiver`
    """
    cdef bint can_receive(self) except -1 nogil:
        return True
    cdef int _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1:
        self.tag = None
        self.attrs.clear()
        return 0
    cdef int _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1:
        self.xml_bytes = self.ptr.p_data
        cdef str data_str = self.xml_bytes.decode('UTF-8')
        if len(data_str):
            tag, attrs = parse_xml(data_str)
            if tag is not None:
                self.tag = tag
                self.attrs = attrs
        if recv_ptr is not NULL:
            NDIlib_recv_free_metadata(recv_ptr, self.ptr)
        return 0


cdef class MetadataSendFrame(MetadataFrame):
    """A MetadataFrame used in :class:`.sender.Sender`

    Arguments:
        tag (str): The xml tag name for this metadata frame
        initdict (dict, optional): Initial attributes for this metadata frame
        **kwargs: Additional attributes for this metadata frame

    The attributes in this class can be set using dict-like methods::

        >>> metadata_frame['program_tally'] = "false"
        >>> metadata_frame.update({'preview_tally':'true'})
    """
    def __init__(self, str tag, object initdict=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.tag = tag
        cdef dict d = {}
        if initdict is not None:
            if not isinstance(initdict, dict):
                raise TypeError(f'initdict must be a dict, got {type(initdict)}')
            d.update(initdict)
        d.update(kwargs)
        self.attrs.update(d)
        self._serialize()

    def set_tag(self, str tag):
        """Set the xml tag name for this metadata frame
        """
        super().set_tag(tag)
        self._serialize()

    def __setitem__(self, str key, str value):
        self.attrs[key] = value
        self._serialize()

    def update(self, dict other):
        """Update the attributes in this metadata frame with the items in `other`
        """
        self._update(other)

    cdef int _update(self, dict other) except -1:
        self.attrs.update(other)
        self._serialize()
        return 0

    def clear(self):
        """Clear the tag and attributes in this metadata frame
        """
        self._clear()

    cdef int _clear(self) except -1:
        self.tag = ''
        self.attrs.clear()
        self._serialize()
        return 0

    cdef bint _serialize(self) except -1:
        cdef bint has_attrs = len(self.attrs) > 0, has_tag = len(self.tag) > 0
        cdef str key, val, result_str = ''

        if has_tag:
            if has_attrs:
                result_str = ' '.join([f'{key}="{val}"' for key, val in self.attrs.items()])
            result_str = f'<{self.tag} {result_str}/>'
            self.xml_bytes = result_str.encode('UTF-8')
            self.ptr.p_data = <char*>self.xml_bytes.c_str()
            self.ptr.length = len(self.xml_bytes) + 1
        else:
            self.xml_bytes = b''
            self.ptr.p_data = <char*>self.xml_bytes.c_str()
            self.ptr.length = 0
        return has_tag


def test():
    import time
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    cdef MetadataRecvFrame mf = MetadataRecvFrame()
    cdef bytes xml_b = b'<ndi_tally_echo on_program="true" on_preview="false"/>'
    cdef char* xml_c = xml_b
    # cdef char* xml_str = xml_b
    mf.ptr.p_data = <char*>mem_alloc(sizeof(char) * len(xml_b))
    cdef char** ptr1 = &xml_c
    cdef char** ptr2 = &(mf.ptr.p_data)
    print('copy')
    time.sleep(.1)
    strcpy(ptr2[0], ptr1[0])
    print('copied')
    time.sleep(.1)
    # mf.ptr.p_data = xml_b
    # mf.ptr.length = len(xml_b)
    # try:
    print('parsing')
    time.sleep(.1)
    # cdef cpp_string tag_name_c

    # tag_name_c = _parse_metadata(mf.ptr.p_data, &(mf.attrib_map))
    # mf.tag_name = tag_name_c
    mf._process_incoming(recv_ptr)
    print('parsed')
    time.sleep(.1)
    print(mf.tag)
    print(mf.attrs)
    # cdef dict attrs = mf.attribs()
    # print(attrs)
    # print(mf.get_tag())
    time.sleep(.1)
    assert mf.tag == 'ndi_tally_echo'
    assert mf['on_program'] == 'true'
    assert mf.get('on_preview') == 'false'
    # finally:
    #     mf.ptr.p_data = NULL
