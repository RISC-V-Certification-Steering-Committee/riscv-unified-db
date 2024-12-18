# frozen_string_literal: true

require_relative "portfolio"

# A profile class consists of a number of releases each with set of profiles.
# For example, the RVA profile class has releases such as RVA20, RVA22, RVA23
# that each include an unprivileged profile (e.g., RVA20U64) and one more
# privileged profiles (e.g., RVA20S64).
class ProfileClass < PortfolioClass
  # @return [String] Name of the class
  def marketing_name = @data["marketing_name"]

  # @return [Company] Company that created the profile
  def company = Company.new(@data["company"])

  # @return [License] Documentation license
  def doc_license
    License.new(@data["doc_license"])
  end

  # @return [Array<ProfileRelease>] Defined profile releases in this profile class
  def profile_releases
    return @profile_releases unless @profile_releases.nil?

    @profile_releases = @cfg_arch.profile_releases.select { |pr| pr.profile_class.name == name }

    @profile_releases
  end

  # @return [Array<Profile>] All profiles in this profile class (for all releases).
  def profiles
    return @profiles unless @profiles.nil?

    @profiles = []
    @cfg_arch.profiles.each do |profile|
      if profile.profile_class.name == name
        @profiles << profile
      end
    end

    @profiles
  end

  # @return [Array<Extension>] List of all extensions referenced by the class
  def referenced_extensions
    return @referenced_extensions unless @referenced_extensions.nil?

    @referenced_extensions = []
    profiles.each do |profile|
      @referenced_extensions += profile.in_scope_extensions
    end

    @referenced_extensions.uniq!(&:name)

    @referenced_extensions
  end

end

# A profile release consists of a number of releases each with one or more profiles.
# For example, the RVA20 profile release has profiles RVA20U64 and RVA20S64.
# Note there is no Portfolio* base class for a ProfileRelease to inherit from since there is no
# equivalent to a ProfileRelease in a Certificate so no potential for a shared base class.
class ProfileRelease < DatabaseObjectect
  def marketing_name = @data["marketing_name"]
  def introduction = @data["introduction"]
  def state = @data["state"]

  # @return [Date] Ratification date
  # @return [nil] if the profile is not ratified
  def ratification_date
    return nil if @data["ratification_date"].nil?

    Date.parse(@data["ratification_date"])
  end

  # @return [Array<Person>] Contributors to the profile spec
  def contributors
    @data["contributors"].map { |data| Person.new(data) }
  end

  # @return [ProfileClass] Profile Class that this ProfileRelease belongs to
  def profile_class
    profile_class = @cfg_arch.profile_class(@data["class"])
    raise "No profile class named '#{@data["class"]}'" if profile_class.nil?

    profile_class
  end

  # @return [Array<Profile>] All profiles in this profile release
  def profiles
    return @profiles unless @profiles.nil?

    @profiles = []
    @data["profiles"].each do |profile_ref|
      @profiles << @cfg_arch.ref(profile_ref["$ref"])
    end
    @profiles
  end

  # @return [Array<Extension>] List of all extensions referenced by the release
  def referenced_extensions
    return @referenced_extensions unless @referenced_extensions.nil?

    @referenced_extensions = []
    profiles.each do |profile|
      @referenced_extensions += profile.in_scope_extensions
    end

    @referenced_extensions.uniq!(&:name)

    @referenced_extensions
  end
end

# Representation of a specific profile in a profile release.
class Profile < PortfolioInstance

  # @return [String] The marketing name of the Profile
  def introduction = @data["introduction"]
  def marketing_name = @data["marketing_name"]

  # @return [ProfileRelease] The profile release this profile belongs to
  def profile_release
    profile_release = @cfg_arch.ref(@data["release"]["$ref"])
    raise "No profile release named '#{@data["release"]["$ref"]}'" if profile_release.nil?

    profile_release
  end

  # @return [ProfileClass] The profile class this profile belongs to
  def profile_class = profile_release.profile_class

  # @return ["M", "S", "U", "VS", "VU"] Privilege mode for the profile
  def mode
    @data["mode"]
  end

  # @return [32, 64] The base XLEN for the profile
  def base
    @data["base"]
  end

  # @return [Array<Extension>] List of all extensions referenced by the profile
  def referenced_extensions = in_scope_extensions

  # Too complicated to put in profile ERB template.
  # @param presence_type [String]
  # @param heading_level [Integer]
  # @return [Array<String>] Each array entry is a line
  def extensions_to_adoc(presence_type, heading_level)
    ret = []

    presence_ext_reqs = in_scope_ext_reqs(presence_type)
    plural = (presence_ext_reqs.size == 1) ? "" : "s"
    ret << "The #{marketing_name} Profile has #{presence_ext_reqs.size} #{presence_type} extension#{plural}."
    ret << ""

    unless presence_ext_reqs.empty?
      if (presence_type == ExtensionPresence.optional) && uses_optional_types?
        # Iterate through each optional type. Use object version (not string) to get
        # precise comparisons (i.e., presence string and optional type string).
        ExtensionPresence.optional_types_obj.each do |optional_type_obj|
          optional_type_ext_reqs = in_scope_ext_reqs(optional_type_obj)
          unless optional_type_ext_reqs.empty?
            ret << ""
            ret << ("=" * heading_level) + " #{optional_type_obj.optional_type.capitalize} Options"
            optional_type_ext_reqs.each do |ext_req|
              ret << ext_req_to_adoc(ext_req)
              ret << ext_note_to_adoc(ext_req.name)
            end # each ext_req
          end # unless optional_type_ext_reqs empty

          # Add extra notes that just belong to just this optional type.
          extra_notes_for_presence(optional_type_obj)&.each do |extra_note|
            ret << "NOTE: #{extra_note.text}"
            ret << ""
          end # each extra_note
        end # each optional_type_obj
      else # don't bother with optional types
        presence_ext_reqs.each do |ext_req|
          ret << ext_req_to_adoc(ext_req)
          ret << ext_note_to_adoc(ext_req.name)
        end # each ext_req
      end # checking for optional types
    end # presence_ext_reqs isn't empty

    # Add extra notes that just belong to this presence.
    # Use object version (not string) of presence to avoid adding extra notes
    # already added for optional types if they are in use.
    extra_notes_for_presence(ExtensionPresence.new(presence_type))&.each do |extra_note|
      ret << "NOTE: #{extra_note.text}"
      ret << ""
    end # each extra_note

    ret
  end

  # @param ext_req [ExtensionRequirement]
  # @return [Array<String>]
  def ext_req_to_adoc(ext_req)
    ret = []

    ext = cfg_arch.extension(ext_req.name)
    ret << "* *#{ext_req.name}* " + (ext.nil? ? "" : ext.long_name)
    ret << "+"
    ret << "Version #{ext_req.requirement_specs}"

    ret
  end

  # @param ext_name [String]
  # @return [Array<String>]
  def ext_note_to_adoc(ext_name)
    ret = []

    unless extension_note(ext_name).nil?
      ret << "+"
      ret << "[NOTE]"
      ret << "--"
      ret << extension_note(ext_name)
      ret << "--"
    end

    ret
  end
end
