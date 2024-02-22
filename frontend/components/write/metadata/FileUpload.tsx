import { ArrowUpIcon } from "@chakra-ui/icons";
import {
  ButtonProps,
  FormControl,
  FormControlProps,
  IconButton,
  InputGroup,
  useToast,
} from "@chakra-ui/react";
import { useField } from "formik";
import React, { ChangeEvent, ForwardedRef, useRef, useState } from "react";
import { useNotaForm } from "../../../context/NotaFormProvider";

type FileUploadProps = {
  accept?: string;
  multiple?: boolean;
  name: string;
};

export type FileControlProps = FormControlProps &
  FileUploadProps & { buttonProps?: ButtonProps };

export const FileControl: React.FC<FileControlProps> = React.forwardRef(
  (props: FileControlProps, ref: ForwardedRef<HTMLInputElement>) => {
    const {
      name,
      label,
      buttonProps,
      multiple = false,
      accept = ".jpg,.jpeg,.png,.gif,.pdf,.docx,.csv",
      ...rest
    } = props;
    const [{ onChange, ...field }, , { setValue }] = useField(name);
    const inputRef = useRef<HTMLInputElement | null>(null);
    const toast = useToast();
    const { file } = useNotaForm();

    const handleClick = () => {
      inputRef.current?.click();
    };

    const handleChange = (value: ChangeEvent<HTMLInputElement>) => {
      if (value.target.files?.[0] && value.target.files?.[0].size < 5000000) {
        // TODO: lighthouse upload
        setFileName(value.target.files?.[0].name);
        value.target.files && setValue(value.target.files?.[0]);
      } else {
        toast({
          title: "File too large (max size 10MB)",
          status: "error",
          duration: 3000,
          isClosable: true,
        });
      }
    };

    const [fileName, setFileName] = useState<string | undefined>(file?.name);

    return (
      <FormControl name={name} label={label} {...rest} {...ref} mt={8}>
        <InputGroup onClick={handleClick}>
          <input
            onChange={handleChange}
            type="file"
            accept={accept}
            multiple={multiple}
            id={name}
            ref={inputRef}
            hidden
          />
          <IconButton
            variant={"outline"}
            aria-label="Upload"
            {...buttonProps}
            {...field}
            icon={<ArrowUpIcon />}
            isLoading={false}
          ></IconButton>
        </InputGroup>
      </FormControl>
    );
  }
);

export default FileControl;
